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
import { DepositQueueTargetsV2 } from "./DepositQueueTargetsV2.sol";
import { IStrategy } from "contracts/EigenLayer/interfaces/IStrategy.sol";
import {
    IDelegationManager
} from "../../../contracts/EigenLayer/interfaces/IDelegationManager.sol";
import { IEigenPodManager } from "../../../contracts/EigenLayer/interfaces/IEigenPodManager.sol";
import { IStrategyManager } from "../../../contracts/EigenLayer/interfaces/IStrategyManager.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { StrategyBaseTVLLimits } from "eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";
import { WithdrawQueue } from "contracts/Withdraw/WithdrawQueue.sol";
import { WithdrawQueueStorageV1 } from "contracts/Withdraw/WithdrawQueueStorage.sol";
import { SetupV2 } from "./SetupV2.sol";
import "../../mocks/MockAggregatorV3.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargetsV2 is BaseTargetFunctions, SetupV2 {
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
    address immutable TOKEN_BURN_ADDRESS = address(0x1);

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
        // OperatorDelegators are what make the call to deploy EigenPod and so are the owner of the created pod
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        address pod = getPodForOwner(address(operatorDelegator));

        vm.prank(pod); // need to prank as pod to call functions in EigenPodManager that modify accounting
        slashNative(address(operatorDelegator));
    }

    /// @notice simulates and AVS slashing event on EigenLayer for native ETH and LSTs held by an OperatorDelegator
    function restakeManager_slash_AVS(uint256 nativeSlashAmount, uint256 lstSlashAmount) public {
        // NOTE: Because current deployment setup only sets one collateral token for a given OperatorDelegator there are only two possible stakes that can be slashed (LST and native ETH),
        //       but if an OperatorDelegator has multiple strategies associated with it, this logic will have to be refactored to appropriately slash each.
        //       The slashings conducted are dependant on the shares the OperatorDelegator has in each
        uint256 nativeEthShares = uint256(
            eigenPodManager.podOwnerShares(address(activeOperatorDelegator))
        );
        uint256 lstShares = activeStrategy.shares(address(activeOperatorDelegator));

        // Slash native ETH if OperatorDelegator has any staked in EigenLayer
        if (nativeEthShares > 0) {
            // user can be slashed a max amount of their entire stake
            nativeSlashAmount = nativeSlashAmount % nativeEthShares;

            // shares are 1:1 with ETH in EigenPod so can slash the share amount directly
            ethPOSDepositMock.slash(nativeSlashAmount);

            // update the OperatorDelegator's share balance in EL by calling EigenPodManager as the pod
            address podAddress = address(eigenPodManager.getPod(address(activeOperatorDelegator)));
            vm.prank(podAddress);
            eigenPodManager.recordBeaconChainETHBalanceUpdate(
                address(activeOperatorDelegator),
                -int256(nativeSlashAmount)
            );
        }

        // Slash LST if OperatorDelegator has any staked in EigenLayer
        if (lstShares > 0) {
            uint256 slashingAmountLSTShares = lstSlashAmount % lstShares;
            // convert share amount to slash to collateral token
            uint amountLSTToken = activeStrategy.sharesToUnderlyingView(slashingAmountLSTShares);

            // burn tokens in strategy to ensure they don't effect accounting
            vm.prank(address(activeStrategy));
            IERC20(activeCollateralToken).transfer(TOKEN_BURN_ADDRESS, amountLSTToken);

            // remove shares to update operatorDelegator's accounting
            vm.prank(address(delegation));
            _removeSharesFromStrategyManager(
                address(activeOperatorDelegator),
                address(activeStrategy),
                slashingAmountLSTShares
            );
        }
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

    /**
        Deployment Using Fuzzer
    */
    /// @notice deploys a collateral token with a corresponding strategy (in EigenLayer) and OperatorDelegator
    // NOTE: can add extra source of randomness by fuzzing the allocation parameters for OperatorDelegator
    function restakeManager_deployTokenStratOperatorDelegator() public {
        // NOTE: TEMPORARY
        require(!singleDeployed); // This bricks the function for Medusa
        // if singleDeployed, this deploys one token, one strategy, one Operator

        if (RECON_USE_SINGLE_DEPLOY) {
            singleDeployed = true;
        }

        if (RECON_USE_HARDCODED_DECIMALS) {
            decimals = 18;
        }

        initialMintPerUsers = 1_000_000e18;

        // deploy collateral token
        {
            // concatenate length of token array for token name and symbol
            string memory tokenNumber = (collateralTokens.length + 1).toString();
            string memory tokenName = string(abi.encodePacked("Collateral Token ", tokenNumber));
            string memory tokenSymbol = string(abi.encodePacked("CT", tokenNumber));

            collateralTokens.push(new MockERC20(tokenName, tokenSymbol, decimals));
            collateralTokens[collateralTokens.length - 1].mint(address(this), initialMintPerUsers);
            collateralTokens[collateralTokens.length - 1].approve(
                address(restakeManager),
                type(uint256).max
            );
        }

        uint256 collateralTokenslength = collateralTokens.length;

        // deploy collateral token oracle
        {
            vm.warp(1524785992); // warps to echidna's initial start time
            MockERC20 collateralTokenForOracle = collateralTokens[collateralTokenslength - 1];
            MockAggregatorV3 oracleForCollateralToken = new MockAggregatorV3(
                18, // decimals
                "CT1 price oracle", // description
                1, // version
                1e18, // answer
                block.timestamp, // startedAt
                block.timestamp // updatedAt
            );

            collateralTokenOracles[address(collateralTokenForOracle)] = oracleForCollateralToken;

            renzoOracle.setOracleAddress(
                collateralTokenForOracle,
                AggregatorV3Interface(address(oracleForCollateralToken))
            );
        }

        // console2.log(
        //     "oracle from mapping: ",
        //     address(collateralTokenOracles[address(collateralTokens[collateralTokenslength - 1])])
        // );

        // deploy EigenLayer strategy for token
        {
            // NOTE: this can be refactored into an function in EigenLayer setup that handles this to keep things properly separated
            baseStrategyImplementation = new StrategyBaseTVLLimits(strategyManager);

            deployedStrategies.push(
                IStrategy(
                    address(
                        StrategyBaseTVLLimits(
                            address(
                                new TransparentUpgradeableProxy(
                                    address(baseStrategyImplementation),
                                    address(eigenLayerProxyAdmin),
                                    abi.encodeWithSelector(
                                        StrategyBaseTVLLimits.initialize.selector,
                                        // NOTE: fuzzing these next two input values could allow better evaluation of possible combinations due to TVL limits
                                        type(uint256).max,
                                        type(uint256).max,
                                        IERC20(collateralTokens[collateralTokenslength - 1]),
                                        eigenLayerPauserReg
                                    )
                                )
                            )
                        )
                    )
                )
            );
        }

        // set the strategy whitelist in strategyManager
        // NOTE: toggling third party transfers could be a good target for fuzzing

        // only need to add one strategy at a time
        bool[] memory thirdPartyTransfers = new bool[](1); // default to allowing third party transfers
        address[] memory deployedStrategiesTemp = new address[](1);

        // adds the most recently deployed strategy to the array that is used to set strategies in StrategyManager
        deployedStrategiesTemp[0] = address(deployedStrategies[deployedStrategies.length - 1]);
        _addStrategiesToDepositWhitelist(deployedStrategiesTemp, thirdPartyTransfers);

        IStrategy addedStrategy = deployedStrategies[deployedStrategies.length - 1];

        // NOTE: this logic might make more sense to have in switcher because the token shouldn't be added to the renzo system here
        // set collateral token in WithdrawQueue
        {
            // withdrawBuffer only needs length 1 because updating single asset and target in each deploy
            WithdrawQueueStorageV1.TokenWithdrawBuffer[]
                memory withdrawBuffer = new WithdrawQueueStorageV1.TokenWithdrawBuffer[](1);

            withdrawBuffer[0] = WithdrawQueueStorageV1.TokenWithdrawBuffer(
                address(collateralTokens[collateralTokenslength - 1]),
                initialBufferTarget
            );

            // initialize the withdrawQueue with new withdrawBuffer
            withdrawQueue.updateWithdrawBufferTarget(withdrawBuffer);
            // console2.log(
            //     "buffer target for collateral asset: ",
            //     withdrawQueue.withdrawalBufferTarget(address(collateralTokens[0]))
            // );
        }

        // Deploy OperatorDelegator and set the token strategy for it
        {
            operatorDelegatorImplementation = new OperatorDelegator();

            operatorDelegators.push(
                OperatorDelegator(
                    payable(
                        address(
                            new TransparentUpgradeableProxy(
                                address(operatorDelegatorImplementation),
                                address(renzoProxyAdmin),
                                abi.encodeWithSelector(
                                    OperatorDelegator.initialize.selector,
                                    roleManager,
                                    IStrategyManager(address(strategyManager)),
                                    restakeManager,
                                    IDelegationManager(address(delegation)),
                                    IEigenPodManager(address(eigenPodManager))
                                )
                            )
                        )
                    )
                )
            );

            // console2.log("ODs length: ", operatorDelegators.length);
        }

        // If this is the first deploy, use the switcher to set OperatorDelegator and CollateralToken
        if (!hasDoneADeploy) {
            restakeManager_switchTokenAndDelegator(0, 0);
            hasDoneADeploy = true;
        }
    }

    /// @notice switches the active token and OperatorDelegator in the system
    function restakeManager_switchTokenAndDelegator(
        uint256 operatorDelegatorIndex,
        // uint256 collateralTokenIndex
        uint256 tokenStrategyIndex
    ) public {
        // NOTE: could fuzz operatorDelegatorAllocation for more randomness
        uint256 operatorDelegatorAllocation = 10_000; // 10,000 BP because only using one active OperatorDelegator at a time

        // Add OperatorDelegator and collateral token to RestakeManager
        // NOTE: only remove existing OperatorDelegator and CollateralToken if they've been previously set (not first deployment)
        if (
            restakeManager.getOperatorDelegatorsLength() != 0 &&
            restakeManager.getCollateralTokensLength() != 0
        ) {
            // NOTE: this assumes there is only ever one OperatorDelegator in the array, if this isn't true, this logic will be incorrect
            IOperatorDelegator operatorDelegatorToRemove = restakeManager.operatorDelegators(0);
            // remove previously set OperatorDelegator
            restakeManager.removeOperatorDelegator(operatorDelegatorToRemove);
            // remove previously set collateral token
            IERC20 collateralTokenToRemove = restakeManager.collateralTokens(0);
            restakeManager.removeCollateralToken(collateralTokenToRemove);
        }

        // adds random OperatorDelegator to RestakeManager
        IOperatorDelegator operatorDelegatorToAdd = _getRandomOperatorDelegator(
            operatorDelegatorIndex
        );
        restakeManager.addOperatorDelegator(operatorDelegatorToAdd, operatorDelegatorAllocation);

        // fetches random token strategy and corresponding collateralToken
        IStrategy strategyToAdd = _getRandomTokenStrategy(tokenStrategyIndex);
        IERC20 collateralTokenToAdd = strategyToAdd.underlyingToken();

        // adds random collateral token to the restake manager
        restakeManager.addCollateralToken(collateralTokenToAdd);

        // sets the currently active collateral token and OperatorDelegator for access in tests
        activeOperatorDelegator = OperatorDelegator(payable(address(operatorDelegatorToAdd)));
        activeCollateralToken = MockERC20(address(collateralTokenToAdd));
        activeStrategy = strategyToAdd;

        // set token strategy in the OperatorDelegator
        activeOperatorDelegator.setTokenStrategy(collateralTokenToAdd, strategyToAdd);
    }

    /**
        Utils
    */
    function _getRandomTokenStrategy(uint256 strategyIndex) internal returns (IStrategy strategy) {
        return deployedStrategies[strategyIndex % deployedStrategies.length];
    }
}
