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
    MockERC20 internal activeCollateralToken;
    OperatorDelegator internal activeOperatorDelegator;
    IStrategy internal activeStrategy;
    IStrategy[] internal deployedStrategies;

    // bool immutable RECON_USE_SINGLE_DEPLOY = true;
    // @audit setting this to false see if multiple deploy works
    bool immutable RECON_USE_SINGLE_DEPLOY = false;
    bool immutable RECON_USE_HARDCODED_DECIMALS = true;
    address immutable TOKEN_BURN_ADDRESS = address(0x1);

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

    // @notice simulates a native slashing event on one of the validators that gets created by OperatorDelegator::stakeEth
    function restakeManager_slash_native(uint256 operatorDelegatorIndex) public {
        // OperatorDelegators are what make the call to deploy EigenPod and so are the owner of the created pod
        IOperatorDelegator operatorDelegator = _getRandomOperatorDelegator(operatorDelegatorIndex);

        int256 podOwnerSharesBefore = eigenPodManager.podOwnerShares(address(operatorDelegator));

        // reduces the balance of the deposit contract by the max slashing penalty (1 ETH)
        ethPOSDepositMock.slash(1 ether);

        // update the OperatorDelegator's share balance in EL by calling EigenPodManager as the pod
        address podAddress = address(eigenPodManager.getPod(address(operatorDelegator)));
        vm.prank(podAddress);
        eigenPodManager.recordBeaconChainETHBalanceUpdate(address(operatorDelegator), -1 ether);

        int256 podOwnerSharesAfter = eigenPodManager.podOwnerShares(address(operatorDelegator));

        // check that share allocation is properly decreased
        require(podOwnerSharesAfter < podOwnerSharesBefore, "pod owner shares don't decrease");
    }

    // The following are the only cases that the EigenLayer system would have an effect on balances via slashing,
    // other cases where an amount is deposited but held in a queue would essentially be invisible to EigenLayer and therefore aren't covered here:
    // - Native ETH: OperatorDelegator has created a validator with the staked ETH (at least 32 ETH deposited)
    // - LSTs: OperatorDelegator has received deposits greater than the withdrawQueue buffer amount
    function restakeManager_slash_AVS() public {
        uint256 slashingPercentInBps = 300;

        // NOTE: Because current deployment setup only sets one collateral token for a given OperatorDelegator there are only two possible stakes that can be slashed (LST and native ETH),
        //       but if an OperatorDelegator has multiple strategies associated with it, this logic will have to be refactored to appropriately slash each. The slashings conducted are dependant on the shares the OperatorDelegator has in each
        uint256 nativeEthShares = uint256(
            eigenPodManager.podOwnerShares(address(activeOperatorDelegator))
        );
        uint256 lstShares = activeStrategy.shares(address(activeOperatorDelegator));

        // Slash native ETH if OperatorDelegator has any staked in EigenLayer
        if (nativeEthShares > 0) {
            // calculate the amount to slash from the native ETH share balance
            uint256 slashingAmountNativeShares = (((nativeEthShares * 1e18) *
                slashingPercentInBps) / 10_000) / 1e18;

            // shares are 1:1 with ETH in EigenPod so can slash the share amount directly
            ethPOSDepositMock.slash(slashingAmountNativeShares);

            // update the OperatorDelegator's share balance in EL by calling EigenPodManager as the pod
            address podAddress = address(eigenPodManager.getPod(address(activeOperatorDelegator)));
            vm.prank(podAddress);
            eigenPodManager.recordBeaconChainETHBalanceUpdate(
                address(activeOperatorDelegator),
                -int256(slashingAmountNativeShares)
            );
        }

        // Slash LST if OperatorDelegator has any staked in EigenLayer
        if (lstShares > 0) {
            // calculate the amount to slash from the LST share balance
            uint slashingAmountLSTShares = (((lstShares * 1e18) * slashingPercentInBps) / 10_000) /
                1e18;
            // convert share amount to slash to collateral token
            uint slashingAmountLSTToken = activeStrategy.sharesToUnderlyingView(
                slashingAmountLSTShares
            );

            // burn tokens in strategy to ensure they don't effect accounting
            vm.prank(address(activeStrategy));
            IERC20(activeCollateralToken).transfer(TOKEN_BURN_ADDRESS, slashingAmountLSTToken);

            // remove shares to update operatorDelegator's accounting
            vm.prank(address(delegation));
            _removeSharesFromStrategyManager(
                address(activeOperatorDelegator),
                address(activeStrategy),
                slashingAmountLSTShares
            );
            console2.log(
                "OperatorDelegator LST shares after: ",
                activeStrategy.shares(address(activeOperatorDelegator))
            );
        }
    }

    function restakeManager_LST_discount(uint256 discount) public {
        // assume a max discount of 500 basis points, on par with historical depeg for stETH discussed here: https://medium.com/huobi-research/steth-depegging-what-are-the-consequences-20b4b7327b0c
        discount = discount % 500;

        // get the oracle for the active collateral token and set the price on it
        MockAggregatorV3 activeTokenOracle = collateralTokenOracles[address(activeCollateralToken)];

        // apply discount to current price
        (, int256 currentPrice, , , ) = activeTokenOracle.latestRoundData();

        int256 discountedPrice = currentPrice -
            ((currentPrice * 1e18 * int256(discount)) / 10_000) /
            1e18;

        // set new price in oracle
        activeTokenOracle.setPrice(discountedPrice);
    }

    function restakeManager_LST_rebase(uint256 priceChangePercentage) public {
        // check that the last rebase was > 24 hours ago because rebases only happen once daily when beacon chain ether balance is updated
        // clamp the priceChangePercentage to be within the bounds of a rebase amount in stETH
        // increase the price in the exchange rate of the oracle to reflect the rebase event
    }

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

    function _getRandomTokenStrategy(uint256 strategyIndex) internal returns (IStrategy strategy) {
        return deployedStrategies[strategyIndex % deployedStrategies.length];
    }
}
