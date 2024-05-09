// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { BeforeAfter } from "./BeforeAfter.sol";
import { Properties } from "./Properties.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargets is BaseTargetFunctions, Properties, BeforeAfter {
    function restakeManager_deposit(uint256 tokenIndex, uint256 amount) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));
        restakeManager.deposit(collateralToken, amount);
    }

    function restakeManager_depositReferral(
        uint256 tokenIndex,
        uint256 amount,
        uint256 referralId
    ) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));
        restakeManager.deposit(collateralToken, amount, referralId);
    }

    function restakeManager_depositETH() public payable {
        restakeManager.depositETH();
    }

    function restakeManager_depositETHReferral(uint256 referralId) public payable {
        restakeManager.depositETH(referralId);
    }

    function _getRandomDepositableToken(uint256 tokenIndex) internal view returns (address) {
        return lstAddresses[tokenIndex % lstAddresses.length];
    }
}
