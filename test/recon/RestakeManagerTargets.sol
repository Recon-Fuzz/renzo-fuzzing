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

import { OperatorDelegator } from "contracts/Delegation/OperatorDelegator.sol";
import { IOperatorDelegator } from "../../../contracts/Delegation/IOperatorDelegator.sol";
import { DepositQueueTargets } from "./DepositQueueTargets.sol";
import { IStrategy } from "contracts/EigenLayer/interfaces/IStrategy.sol";
import {
    IDelegationManager
} from "../../../contracts/EigenLayer/interfaces/IDelegationManager.sol";
import { IEigenPodManager } from "../../../contracts/EigenLayer/interfaces/IEigenPodManager.sol";
import { IStrategyManager } from "../../../contracts/EigenLayer/interfaces/IStrategyManager.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StrategyBaseTVLLimits } from "eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";
import { WithdrawQueue } from "contracts/Withdraw/WithdrawQueue.sol";
import { WithdrawQueueStorageV1 } from "contracts/Withdraw/WithdrawQueueStorage.sol";
import { Setup } from "./Setup.sol";
import "../mocks/MockAggregatorV3.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargets is BaseTargetFunctions, Setup {
    using Strings for uint256;

    bool internal singleDeployed;
    bool internal hasDoneADeploy;
    uint8 internal decimals;
    uint256 internal initialMintPerUsers;
    uint256 internal initialBufferTarget = 10_000;
    uint256 internal lastRebase;
    MockERC20 internal activeCollateralToken;
    OperatorDelegator internal activeOperatorDelegator;
    IStrategy internal activeStrategy;
    IStrategy[] internal deployedStrategies;

    // bool immutable RECON_USE_SINGLE_DEPLOY = true;
    // @audit setting this to false see if multiple deploy works
    bool immutable RECON_USE_SINGLE_DEPLOY = false;
    bool immutable RECON_USE_HARDCODED_DECIMALS = true;
    // address immutable TOKEN_BURN_ADDRESS = address(0x1);

    event Debug(uint256 balance);
    event SenderBalance(uint256);

    function restakeManager_deposit(uint256 tokenIndex, uint256 amount) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));

        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        restakeManager.deposit(collateralToken, amount);
    }

    function restakeManager_depositReferral(
        uint256 tokenIndex,
        uint256 amount,
        uint256 referralId
    ) public {
        IERC20 collateralToken = IERC20(_getRandomDepositableToken(tokenIndex));
        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        restakeManager.deposit(collateralToken, amount, referralId);
    }

    function restakeManager_depositETH(uint256 amount) public payable {
        amount = amount % address(this).balance;
        restakeManager.depositETH{ value: amount }();
    }

    function restakeManager_clamped_depositETH() public payable {
        restakeManager.depositETH{ value: 32 ether }();
    }

    function restakeManager_depositETHReferral(uint256 amount, uint256 referralId) public payable {
        amount = amount % address(this).balance;
        restakeManager.depositETH{ value: msg.value }(referralId);
    }

    function restakeManager_setTokenTvlLimit(uint256 tokenIndex, uint256 amount) public {
        address tokenToLimit = _getRandomDepositableToken(tokenIndex);
        restakeManager.setTokenTvlLimit(IERC20(tokenToLimit), amount);
    }

    /**
        External System Manipulation - see externalities file for more explanation on these
    */

    // NOTE: danger, this allows the fuzzer to fill the buffer but may have unintended side-effects for overall system behavior
    function restakeManager_fillBuffer(uint256 collateralTokenIndex) public {
        address collateralToken = _getRandomDepositableToken(collateralTokenIndex);

        uint256 bufferToFill = depositQueue.withdrawQueue().getBufferDeficit(
            address(collateralToken)
        );

        // the target contract gets minted both of the collateral tokens in setup
        IERC20(collateralToken).transfer(address(depositQueue.withdrawQueue()), bufferToFill);
    }

    /// @notice simulates accrual of staking rewards that get sent to DepositQueue
    /// @dev this is needed to allow coverage of the depositTokenRewardsFromProtocol function
    function restakeManager_simulateRewardsAccrual(
        uint256 collateralTokenIndex,
        uint256 amount
    ) public {
        address collateralToken = _getRandomDepositableToken(collateralTokenIndex);
        amount = amount % IERC20(collateralToken).balanceOf(address(this));

        IERC20(collateralToken).transfer(address(depositQueue), amount);
    }

    /// @notice simulates a native slashing event on one of the validators that gets created by OperatorDelegator::stakeEth
    function restakeManager_slash_native(uint256 operatorDelegatorIndex) public {
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        slashNative(address(operatorDelegator));
    }

    /// @notice simulates and AVS slashing event on EigenLayer for native ETH and LSTs held by an OperatorDelegator
    function restakeManager_slash_AVS(
        uint256 operatorDelegatorIndex,
        uint256 nativeSlashAmount,
        uint256 lstSlashAmount
    ) public {
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        slashAVS(address(operatorDelegator), nativeSlashAmount, lstSlashAmount);
    }

    /// @notice simulates a discount in the price of an LST token in the system via the price returned by the oracle
    function restakeManager_LST_discount(int256 discount) public {
        // get the oracle for the active collateral token and set the price on it
        MockAggregatorV3 activeTokenOracle = collateralTokenOracles[address(activeCollateralToken)];

        // apply discount to current price
        (, int256 currentPrice, , , ) = activeTokenOracle.latestRoundData();

        // clamp discount up to the current price, allows price to go to a minimum of 0
        discount = discount % currentPrice;

        int256 discountedPrice = currentPrice - discount;

        // set new price in oracle
        activeTokenOracle.setPrice(discountedPrice);
    }

    /// @notice simulates a rebase of an LST token as a corresponding increase in the price of the LST token relative to ezETH
    /// @dev see shared_LST_interface for a more detailed description of the design decisions
    function restakeManager_LST_rebase(int256 rebasedPrice) public {
        // check that the last rebase was > 24 hours ago because rebases only happen once daily when beacon chain ether balance is updated
        require(block.timestamp >= lastRebase + 24 hours);

        // get the oracle for the active collateral token and set the price on it
        MockAggregatorV3 activeTokenOracle = collateralTokenOracles[address(activeCollateralToken)];

        // increase the price in the exchange rate of the oracle to reflect the rebase event
        (, int256 currentPrice, , , ) = activeTokenOracle.latestRoundData();
        require(rebasedPrice > currentPrice); // rebase increases price, decrease in price would be handled by the restakeManager_LST_discount function

        // set new price in oracle
        activeTokenOracle.setPrice(rebasedPrice);

        // set new last rebase time
        lastRebase = block.timestamp;
    }
}
