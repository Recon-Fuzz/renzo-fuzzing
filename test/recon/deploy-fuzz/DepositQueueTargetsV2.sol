// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SetupV2 } from "./SetupV2.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";

abstract contract DepositQueueTargetsV2 is SetupV2 {
    // NOTE: this is a privileged function that's called by an ERC20RewardsAdmin admin to sweep ERC20 rewards tokens into RestakeManager
    function depositQueue_depositTokenRewardsFromProtocol(uint256 tokenIndex) public {
        address tokenToDeposit = _getRandomDepositableToken(tokenIndex);

        // the call in depositQueue makes a call to depositTokenRewardsFromProtocol
        depositQueue.sweepERC20(IERC20(tokenToDeposit));
    }

    // NOTE: this needs to be included to complete the native ETH staking process
    // @audit currently ETH deposit contract is being mocked by ETHPOSDepositMock so signature values are irrelevant
    function depositQueue_stakeEthFromQueue(
        uint256 operatorDelegatorIndex,
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) public {
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        depositQueue.stakeEthFromQueue(operatorDelegator, pubkey, signature, depositDataRoot);
    }
}
