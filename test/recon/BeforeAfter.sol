// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Setup } from "./Setup.sol";
import { WithdrawQueueStorageV1 } from "../../contracts/Withdraw/WithdrawQueueStorage.sol";
import { console2 } from "forge-std/console2.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        WithdrawQueueStorageV1.WithdrawRequest withdrawRequest;
    }

    Vars internal _before;
    Vars internal _after;

    function __before(address user, uint256 withdrawRequestIndex) internal {
        (
            address collateralToken,
            uint256 withdrawRequestID,
            uint256 amountToRedeem,
            uint256 ezETHLocked,
            uint256 createdAt
        ) = withdrawQueue.withdrawRequests(user, withdrawRequestIndex);

        WithdrawQueueStorageV1.WithdrawRequest memory withdrawRequest = WithdrawQueueStorageV1
            .WithdrawRequest({
                collateralToken: collateralToken,
                withdrawRequestID: withdrawRequestID,
                amountToRedeem: amountToRedeem,
                ezETHLocked: ezETHLocked,
                createdAt: createdAt
            });

        _before.withdrawRequest = withdrawRequest;
    }

    function __after(address user, uint256 withdrawRequestIndex) internal {
        (
            address collateralToken,
            uint256 withdrawRequestID,
            uint256 amountToRedeem,
            uint256 ezETHLocked,
            uint256 createdAt
        ) = withdrawQueue.withdrawRequests(user, withdrawRequestIndex);

        WithdrawQueueStorageV1.WithdrawRequest memory withdrawRequest = WithdrawQueueStorageV1
            .WithdrawRequest({
                collateralToken: collateralToken,
                withdrawRequestID: withdrawRequestID,
                amountToRedeem: amountToRedeem,
                ezETHLocked: ezETHLocked,
                createdAt: createdAt
            });

        _after.withdrawRequest = withdrawRequest;
    }
}
