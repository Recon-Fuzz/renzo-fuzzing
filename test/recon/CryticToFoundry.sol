// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { RestakeManagerTargets } from "./RestakeManagerTargets.sol";
import { AdminTargets } from "./AdminTargets.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";
import { WithdrawQueueTargets } from "./WithdrawQueueTargets.sol";
import "../mocks/MockAggregatorV3.sol";

contract CryticToFoundry is
    Test,
    RestakeManagerTargets,
    AdminTargets,
    DepositQueueTargets,
    WithdrawQueueTargets,
    FoundryAsserts
{
    function setUp() public {
        setup();
    }

    function test_native_slashing() public {
        // user makes a deposit sufficient for creating a new validator
        restakeManager.depositETH{ value: 32 ether }();

        // DepositQueue calls stakeEthInOperatorDelegator to create a new validator for OperatorDelegator at index 0
        bytes memory pubkey = hex"123456";
        bytes memory signature = hex"789101";
        bytes32 dataRoot = bytes32(uint256(0xbeef));

        address operatorDelegator = address(_getRandomOperatorDelegator(0));
        depositQueue_stakeEthFromQueue(0, pubkey, signature, dataRoot);

        uint256 depositContractBalanceBefore = address(ethPOSDepositMock).balance;
        int256 podOwnerSharesBefore = eigenPodManager.podOwnerShares(operatorDelegator);

        // slash the validator for OperatorDelegator at index 0
        restakeManager_slash_native(0);

        uint256 depositContractBalanceAfter = address(ethPOSDepositMock).balance;
        int256 podOwnerSharesAfter = eigenPodManager.podOwnerShares(operatorDelegator);

        // slashing event reduces the balance associated with the validator in EL
        console2.log("balance before: ", depositContractBalanceBefore);
        console2.log("balance after: ", depositContractBalanceAfter);
        assertTrue(
            depositContractBalanceBefore > depositContractBalanceAfter,
            "deposit contract balance doesn't decrease"
        );
        assertTrue(podOwnerSharesBefore > podOwnerSharesAfter, "pod owner shares don't decrease");
    }

    function test_avs_slashing() public {
        // DEPOSIT
        // make a deposit into the system with LST
        restakeManager_deposit(0, 100_000);

        // make a deposit into system with ETH
        restakeManager.depositETH{ value: 32 ether }();

        // DepositQueue calls stakeEthInOperatorDelegator to create a new validator for OperatorDelegator at index 0
        bytes memory pubkey = hex"123456";
        bytes memory signature = hex"789101";
        bytes32 dataRoot = bytes32(uint256(0xbeef));

        depositQueue_stakeEthFromQueue(0, pubkey, signature, dataRoot);

        // SLASH
        address operatorDelegator = address(_getRandomOperatorDelegator(0));

        int256 podOwnerSharesBefore = eigenPodManager.podOwnerShares(address(operatorDelegator));
        uint256 lstSharesBefore = strategies[0].shares(address(operatorDelegator));

        restakeManager_slash_AVS(0, 5 ether, 10);

        int256 podOwnerSharesAfter = eigenPodManager.podOwnerShares(address(operatorDelegator));
        uint256 lstSharesAfter = strategies[0].shares(address(operatorDelegator));

        assertTrue(podOwnerSharesBefore > podOwnerSharesAfter, "pod owner shares don't decrease");
        assertTrue(lstSharesBefore > lstSharesAfter, "lst shares don't decrease");
    }

    function test_LST_rebasing() public {
        address collateralToken = _getRandomDepositableToken(0);
        MockAggregatorV3 collateralTokenOracle = collateralTokenOracles[collateralToken];

        (, int256 priceBefore, , , ) = collateralTokenOracle.latestRoundData();
        console2.log("priceBefore: %e", priceBefore);

        restakeManager_LST_rebase(0, 2e18);

        (, int256 priceAfter, , , ) = collateralTokenOracle.latestRoundData();
        console2.log("priceAfter: %e", priceAfter);

        assertTrue(priceBefore != priceAfter, "price doesn't change");
    }

    function test_LST_discounting() public {
        address collateralToken = _getRandomDepositableToken(0);
        MockAggregatorV3 collateralTokenOracle = collateralTokenOracles[collateralToken];

        (, int256 priceBefore, , , ) = collateralTokenOracle.latestRoundData();
        console2.log("priceBefore: ", priceBefore);

        restakeManager_LST_discount(0, 500);

        (, int256 priceAfter, , , ) = collateralTokenOracle.latestRoundData();
        console2.log("priceAfter: ", priceAfter);

        assertTrue(priceBefore != priceAfter, "price doesn't change");
    }

    function test_withdraw() public {
        restakeManager_deposit(0, 42);

        withdrawQueueTargets_withdraw(5, 0);
    }

    function test_claim() public {
        restakeManager_deposit(0, 42);

        withdrawQueueTargets_withdraw(5, 0);
        vm.warp(block.timestamp + 8 days); // warp past withdrawal delay period
        withdrawQueueTargets_claim(0);
    }

    function test_H05_exploit() public {
        // user deposits to receive ezETH
        restakeManager_deposit(0, 30);

        // user triggers a withdrawal
        withdrawQueueTargets_withdraw(5, 0);

        // redeemable amount changes due to slashing
        // NOTE: using the first OD's index
        restakeManager_slash_AVS(0, 0, 15);
        console2.log("reaches end of AVS slash");

        // user claims more than their fair share
        vm.warp(block.timestamp + 8 days); // warp past withdrawal delay period

        // need to update oracle price because it expires after delay
        {
            MockAggregatorV3 collateralTokenOracle1 = collateralTokenOracles[address(stETH)];
            (, int256 currentPrice1, , uint256 timeUpdated1, ) = collateralTokenOracle1
                .latestRoundData();
            collateralTokenOracle1.setPrice(currentPrice1);

            MockAggregatorV3 collateralTokenOracle2 = collateralTokenOracles[address(wbETH)];
            (, int256 currentPrice2, , uint256 timeUpdated2, ) = collateralTokenOracle2
                .latestRoundData();
            collateralTokenOracle2.setPrice(currentPrice2);
        }

        withdrawQueueTargets_claim(0);
    }

    // NOTE: this is needed for handling gas refunds when testing calls to depositQueue_stakeEthFromQueue
    // fallback() external {}
}
