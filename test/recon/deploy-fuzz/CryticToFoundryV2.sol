// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { RestakeManagerTargetsV2 } from "./RestakeManagerTargetsV2.sol";
import { RestakeManagerAdminTargetsV2 } from "./RestakeManagerAdminTargetsV2.sol";
import { DepositQueueTargetsV2 } from "./DepositQueueTargetsV2.sol";
import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";
import "../../mocks/MockAggregatorV3.sol";

contract CryticToFoundryV2 is
    Test,
    RestakeManagerTargetsV2,
    RestakeManagerAdminTargetsV2,
    DepositQueueTargetsV2,
    FoundryAsserts
{
    function setUp() public {
        setup();
    }

    // function test_target_deployer_single() public {
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     // need to check that values are properly set in RestakeManager after deployment
    //     console2.log(restakeManager.getOperatorDelegatorsLength());
    //     console2.log(restakeManager.getCollateralTokensLength());
    //     assertTrue(
    //         restakeManager.getOperatorDelegatorsLength() == 1 &&
    //             restakeManager.getCollateralTokensLength() == 1,
    //         "initial values for OperatorDelegator and CollateralToken not set"
    //     );
    // }

    // // call to deploy shouldn't override set values
    // function test_deploy_multi() public {
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     restakeManager_deployTokenStratOperatorDelegator();

    //     // there should be multiple ODs and tokens in the arrays in target but not in RestakeManager
    //     console2.log("operatorDelegators length: ", operatorDelegators.length);
    //     console2.log("collateralTokens length: ", collateralTokens.length);
    //     assertTrue(operatorDelegators.length == 2, "OperatorDelegator not added to possible set");
    //     assertTrue(collateralTokens.length == 2, "CollateralToken not added to possible set");

    //     console2.log(
    //         "RestakeManager operatorDelegators length: ",
    //         restakeManager.getOperatorDelegatorsLength()
    //     );
    //     console2.log(
    //         "RestakeManager collateralTokens length: ",
    //         restakeManager.getCollateralTokensLength()
    //     );
    //     assertTrue(
    //         restakeManager.getOperatorDelegatorsLength() == 1,
    //         "OperatorDelegator added to RestakeManager"
    //     );
    //     assertTrue(
    //         restakeManager.getCollateralTokensLength() == 1,
    //         "OperatorDelegator added to RestakeManager"
    //     );
    // }

    // // only calling deploy then set should switch the values
    // // NOTE: run this again to ensure it works for multiple strategies
    // function test_deploy_and_set_multi() public {
    //     // deploy first combo
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     console2.log("active operatorDelegator: ", address(restakeManager.operatorDelegators(0)));
    //     console2.log("active collateralToken: ", address(restakeManager.collateralTokens(0)));

    //     // deploy second combo
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     // switch to second combo as active one
    //     restakeManager_switchTokenAndDelegator(1, 1);

    //     console2.log("active operatorDelegator: ", address(restakeManager.operatorDelegators(0)));
    //     console2.log("active collateralToken: ", address(restakeManager.collateralTokens(0)));
    // }

    // // @audit this demonstrates a real issue where if _amount <= bufferToFill in call to RestakeManager::deposit it reverts
    // // can define a property for this where if user bal >= _amount, deposit should never revert
    // function test_deploy_and_deposit_issue1() public {
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     restakeManager_deposit(0, 50);
    // }

    // function test_deploy_and_deposit() public {
    //     restakeManager_deployTokenStratOperatorDelegator();

    //     restakeManager_deposit(0, 10_500);
    // }

    // function test_setPaused() public {
    //     restakeManagerAdmin_setPaused(true);
    // }

    function test_native_slashing() public {
        // need to deploy the system first
        restakeManager_deployTokenStratOperatorDelegator();

        /**
            Setting up validator
        */

        // user makes a deposit sufficient for creating a new validator
        // NOTE: need to call the RestakeManager contract here directly because RestakeManagerTargets is abstract so can't have value passed to it
        restakeManager.depositETH{ value: 32 ether }();

        // @audit try making a deposit directly to queue here to see if it helps with debugging why stakeEthFromQueue always reverts

        // DepositQueue calls stakeEthInOperatorDelegator to create a new validator for OperatorDelegator at index 0
        // NOTE: passing in random values here because mock deposit contract doesn't actually check these
        bytes memory pubkey = hex"123456";
        bytes memory signature = hex"789101";
        bytes32 dataRoot = bytes32(uint256(0xbeef));

        address operatorDelegator = address(_getRandomOperatorDelegator(0));
        // NOTE: the OperatorDelegator is the owner of the created EigenPod
        depositQueue_stakeEthFromQueue(0, pubkey, signature, dataRoot);

        /**
            Slashing the validator
        */
        uint256 depositContractBalanceBefore = address(ethPOSDepositMock).balance;
        int256 podOwnerSharesBefore = eigenPodManager.podOwnerShares(operatorDelegator);

        // slash the validator for OperatorDelegator at index 0
        restakeManager_slash_native();

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
        // DEPLOY
        // need to deploy the system first
        restakeManager_deployTokenStratOperatorDelegator();

        // DEPOSIT
        // make a deposit into the system with LST
        restakeManager_deposit(0, 100_000);

        // make a deposit into system with ETH
        restakeManager.depositETH{ value: 32 ether }();

        // DepositQueue calls stakeEthInOperatorDelegator to create a new validator for OperatorDelegator at index 0
        // NOTE: passing in random values here because mock deposit contract doesn't actually check these
        bytes memory pubkey = hex"123456";
        bytes memory signature = hex"789101";
        bytes32 dataRoot = bytes32(uint256(0xbeef));

        // NOTE: the OperatorDelegator is the owner of the created EigenPod
        depositQueue_stakeEthFromQueue(0, pubkey, signature, dataRoot);

        // SLASH
        int256 podOwnerSharesBefore = eigenPodManager.podOwnerShares(
            address(activeOperatorDelegator)
        );
        uint256 lstSharesBefore = activeStrategy.shares(address(activeOperatorDelegator));
        restakeManager_slash_AVS(5 ether, 10);
        int256 podOwnerSharesAfter = eigenPodManager.podOwnerShares(
            address(activeOperatorDelegator)
        );
        uint256 lstSharesAfter = activeStrategy.shares(address(activeOperatorDelegator));

        assertTrue(podOwnerSharesBefore > podOwnerSharesAfter, "pod owner shares don't decrease");
        assertTrue(lstSharesBefore > lstSharesAfter, "lst shares don't decrease");
    }

    function test_LST_rebasing() public {
        restakeManager_deployTokenStratOperatorDelegator();

        MockAggregatorV3 activeTokenOracle = collateralTokenOracles[address(activeCollateralToken)];

        (, int256 priceBefore, , , ) = activeTokenOracle.latestRoundData();
        console2.log("priceBefore: %e", priceBefore);

        restakeManager_LST_rebase(2e18);

        (, int256 priceAfter, , , ) = activeTokenOracle.latestRoundData();
        console2.log("priceAfter: %e", priceAfter);

        assertTrue(priceBefore != priceAfter, "price doesn't change");
    }

    function test_LST_discounting() public {
        restakeManager_deployTokenStratOperatorDelegator();

        MockAggregatorV3 activeTokenOracle = collateralTokenOracles[address(activeCollateralToken)];

        (, int256 priceBefore, , , ) = activeTokenOracle.latestRoundData();
        console2.log("priceBefore: ", priceBefore);

        restakeManager_LST_discount(500);

        (, int256 priceAfter, , , ) = activeTokenOracle.latestRoundData();
        console2.log("priceAfter: ", priceAfter);

        assertTrue(priceBefore != priceAfter, "price doesn't change");
    }

    function test_depositQueue_stakeEthFromQueue_() public {
        restakeManager_deployTokenStratOperatorDelegator();
        depositQueue_stakeEthFromQueue(
            102844322598394097450761440585839690217595636457847608291537204309013972708233,
            hex"28e7c12c19b7691d48f9394753778f688b982b9e3ef80eb381ed8f7aef9012a09cb5f7ffe07166e150e9f1014af91ebca9884cdd14ff642a2b1852572a6d",
            hex"1918129890ac95c074a4975696fae6a7629da37db6bdee5d1f66cc1715c046c1d4404b5c5e30a3118a011cf68cc82fc929803fa3e4ec77e4d361179c6209ae4f",
            hex"532cfd419b0b52278108e212da092ab27833162165a60006893e5527854fb81f"
        );
    }

    // NOTE: this is needed for handling gas refunds from call to stakeEthFromQueue
    // fallback() external {}
}
