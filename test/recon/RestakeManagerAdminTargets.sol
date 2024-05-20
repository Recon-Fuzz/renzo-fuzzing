// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";
import { BeforeAfter } from "./BeforeAfter.sol";
import { Properties } from "./Properties.sol";
import { IOperatorDelegator } from "../../contracts/Delegation/IOperatorDelegator.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";

// NOTE: RestakeManagerAdmin is set to the target contract in the setup
abstract contract RestakeManagerAdminTargets is
    BaseTargetFunctions,
    Properties,
    BeforeAfter,
    DepositQueueTargets
{
    function restakeManagerAdmin_addOperatorDelegator(
        uint256 operatorDelegatorIndex,
        uint256 allocationBasisPoints
    ) public {
        // TODO: need to fetch one of the valid OperatorDelegators
        IOperatorDelegator newOperatorDelegator = _getRandomOperatorDelegator(
            operatorDelegatorIndex
        );
        restakeManager.addOperatorDelegator(newOperatorDelegator, allocationBasisPoints);
    }

    function restakeManagerAdmin_removeOperatorDelegator(uint256 operatorDelegatorIndex) public {
        IOperatorDelegator operatorDelegatorToRemove = _getRandomOperatorDelegator(
            operatorDelegatorIndex
        );
        restakeManager.removeOperatorDelegator(operatorDelegatorToRemove);
    }

    function restakeManagerAdmin_setOperatorDelegatorAllocation(
        IOperatorDelegator operatorDelegator,
        uint256 allocationBasisPoints
    ) public {
        restakeManager.setOperatorDelegatorAllocation(operatorDelegator, allocationBasisPoints);
    }

    function restakeManagerAdmin_addCollateralToken(uint256 collateralTokenIndex) public {
        address newCollateralTokenAddress = _getRandomDepositableToken(collateralTokenIndex);
        IERC20 newCollateralToken = IERC20(newCollateralTokenAddress);
        restakeManager.addCollateralToken(newCollateralToken);
    }

    function restakeManagerAdmin_removeCollateralToken(uint256 collateralTokenIndex) public {
        address collateralTokenAddressToRemove = _getRandomDepositableToken(collateralTokenIndex);
        IERC20 collateralTokenToRemove = IERC20(collateralTokenAddressToRemove);
        restakeManager.removeCollateralToken(collateralTokenToRemove);
    }
}