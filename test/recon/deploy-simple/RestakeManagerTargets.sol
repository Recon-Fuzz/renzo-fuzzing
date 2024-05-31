// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";
import { Properties } from "./Properties.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargets is BaseTargetFunctions, DepositQueueTargets {
    function restakeManager_deposit(uint256 tokenIndex, uint256 amount) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));
        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        restakeManager.deposit(collateralToken, amount);
    }

    // NOTE: allowing this to use fully random referralId for now, could test depositing for invalid referrals with a properly defined property
    function restakeManager_depositReferral(
        uint256 tokenIndex,
        uint256 amount,
        uint256 referralId
    ) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));
        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        restakeManager.deposit(collateralToken, amount, referralId);
    }

    function restakeManager_depositETH() public payable {
        restakeManager.depositETH{ value: msg.value }();
    }

    function restakeManager_depositETHReferral(uint256 referralId) public payable {
        restakeManager.depositETH{ value: msg.value }(referralId);
    }

    // NOTE: danger, setting TVL limits is probably an action that will be taken by admins infrequently
    // breaking properties that result from this may need a better mechanism for switching limits, potentially a binary for on and off without caring about limit amount
    function restakeManager_setTokenTvlLimit(uint256 tokenIndex, uint256 amount) public {
        address tokenToLimit = _getRandomDepositableToken(tokenIndex);

        restakeManager.setTokenTvlLimit(IERC20(tokenToLimit), amount);
    }

    // NOTE: this is a privileged function that's called by the DepositQueue to sweep ERC20 rewards tokens into RestakeManager
    function restakeManager_depositTokenRewardsFromProtocol(uint256 tokenIndex) public {
        depositQueue_depositTokenRewardsFromProtocol(tokenIndex);
    }

    // NOTE: this needs to be included to complete the native ETH staking process
    // @audit currently ETH deposit contract is being mocked by ETHPOSDepositMock so signature values are irrelevant
    function restakeManager_stakeEthFromQueue(
        uint256 operatorDelegatorIndex,
        bytes memory pubkey,
        bytes memory signature,
        bytes32 depositDataRoot
    ) public {
        depositQueue_stakeEthFromQueue(operatorDelegatorIndex, pubkey, signature, depositDataRoot);
    }

    // NOTE: danger, this allows the fuzzer to fill the buffer but may have unintended side-effects for overall system behavior
    function restakeManager_fillBuffer(uint256 collateralTokenIndex) public {
        address collateralToken = _getRandomDepositableToken(collateralTokenIndex);

        uint256 bufferToFill = depositQueue.withdrawQueue().getBufferDeficit(
            address(collateralToken)
        );

        // the target contract gets minted both of the collateral tokens in setup
        IERC20(collateralToken).transfer(address(depositQueue.withdrawQueue()), bufferToFill);
    }

    // @notice simulates accrual of staking rewards that get sent to DepositQueue
    // @dev this is needed to allow coverage of the depositTokenRewardsFromProtocol function
    function restakeManager_simulateRewardsAccrual(
        uint256 collateralTokenIndex,
        uint256 amount
    ) public {
        address collateralToken = _getRandomDepositableToken(collateralTokenIndex);
        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        IERC20(collateralToken).transfer(address(depositQueue), amount);
    }

    function restakeManager_slash(uint256 amount) public {
        ethPOSDepositMock.slash(amount);
    }
}
