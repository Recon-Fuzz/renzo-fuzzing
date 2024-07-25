// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";
import { console2 } from "forge-std/console2.sol";

import { BeforeAfter } from "./BeforeAfter.sol";
import { Setup } from "./Setup.sol";
import { WithdrawQueueStorageV1 } from "../../contracts/Withdraw/WithdrawQueueStorage.sol";
import "../mocks/MockAggregatorV3.sol";

abstract contract WithdrawQueueTargets is BaseTargetFunctions, Setup, BeforeAfter {
    function withdrawQueueTargets_withdraw(uint256 amount, uint256 tokenIndex) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));

        uint256 availableToWithdraw = withdrawQueue.getAvailableToWithdraw(
            address(collateralToken)
        );

        require(availableToWithdraw > 0);

        amount = amount % availableToWithdraw;
        withdrawQueue.withdraw(amount, address(collateralToken));
    }

    function withdrawQueueTargets_claim(uint256 withdrawRequestIndex) public {
        uint256 withdrawQueueLength = withdrawQueue.getOutstandingWithdrawRequests(address(this)); //assumes the caller of withdraw is always the target contract (no other actors)
        withdrawRequestIndex = withdrawRequestIndex % withdrawQueueLength;

        (
            address collateralToken,
            uint256 withdrawRequestID,
            uint256 amountToRedeem,
            uint256 ezETHLocked,
            uint256 createdAt
        ) = withdrawQueue.withdrawRequests(address(this), withdrawRequestIndex);

        WithdrawQueueStorageV1.WithdrawRequest memory withdrawRequest = WithdrawQueueStorageV1
            .WithdrawRequest({
                collateralToken: collateralToken,
                withdrawRequestID: withdrawRequestID,
                amountToRedeem: amountToRedeem,
                ezETHLocked: ezETHLocked,
                createdAt: createdAt
            });

        withdrawQueue.claim(withdrawRequestIndex);

        // check that user can't withdraw more than the expected amount when they initially submitted a withdrawal request
        // the amountToRedeem if recalculated after should be the same as the initial amountToRedeem
        uint256 initialAmountToRedeem = withdrawRequest.amountToRedeem;
        uint256 initialezETHLocked = withdrawRequest.ezETHLocked;

        // calculate how much the amount to redeem would be on claim
        (, , uint256 totalTVL) = restakeManager.calculateTVLs();
        uint256 currentAmountToRedeem = renzoOracle.calculateRedeemAmount(
            initialezETHLocked,
            ezETH.totalSupply(),
            totalTVL
        );

        // this could be improved by allowing for a margin that accounts for new ezETH minted/burned between call to withdrawal and claim
        eq(
            initialAmountToRedeem,
            currentAmountToRedeem,
            "user can claim more than their fair share"
        );
    }
}
