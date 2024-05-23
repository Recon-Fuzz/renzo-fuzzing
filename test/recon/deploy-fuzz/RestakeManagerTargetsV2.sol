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
import { IStrategy } from "eigenlayer/contracts/interfaces/IStrategy.sol";
import {
    IDelegationManager
} from "../../../contracts/EigenLayer/interfaces/IDelegationManager.sol";
import { IEigenPodManager } from "../../../contracts/EigenLayer/interfaces/IEigenPodManager.sol";
import { IStrategyManager } from "../../../contracts/EigenLayer/interfaces/IStrategyManager.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { StrategyBaseTVLLimits } from "eigenlayer/contracts/strategies/StrategyBaseTVLLimits.sol";
import { WithdrawQueue } from "contracts/Withdraw/WithdrawQueue.sol";
import { WithdrawQueueStorageV1 } from "contracts/Withdraw/WithdrawQueueStorage.sol";
import "../../mocks/MockAggregatorV3.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargetsV2 is BaseTargetFunctions, DepositQueueTargetsV2 {
    using Strings for uint256;

    bool internal hasDoneADeploy;
    uint8 internal decimals;
    uint256 internal initialMintPerUsers;
    uint256 internal initialBufferTarget = 10_000;
    MockERC20 internal activeCollateralToken;
    OperatorDelegator internal activeOperatorDelegator;

    mapping(address => MockAggregatorV3) internal collateralTokenOracles;
    MockERC20[] internal collateralTokens;
    IStrategy[] internal deployedStrategies;

    bool immutable RECON_USE_SINGLE_DEPLOY = true;
    bool immutable RECON_USE_HARDCODED_DECIMALS = true;

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

    function restakeManager_slash() public {
        ethPOSDepositMock.slash();
    }

    // NOTE: can add extra source of randomness by fuzzing the allocation parameters for OperatorDelegator
    function deployTokenStratOperatorDelegator() public {
        // NOTE: TEMPORARY
        require(!hasDoneADeploy); // This bricks the function for Medusa
        // if hasDoneADeploy, this deploys one token, one strategy, one Operator

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

        {
            // deploy EigenLayer strategy for token
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
        bool[] memory thirdPartyTransfers = new bool[](deployedStrategies.length); // default to allowing third party transfers

        strategyManager.addStrategiesToDepositWhitelist(deployedStrategies, thirdPartyTransfers);
        // console2.log(
        //     "strategy whitelisted for deposit: ",
        //     strategyManager.strategyIsWhitelistedForDeposit(deployedStrategies[0])
        // );

        {
            // set collateral token in WithdrawQueue
            WithdrawQueueStorageV1.TokenWithdrawBuffer[]
                memory withdrawBuffer = new WithdrawQueueStorageV1.TokenWithdrawBuffer[](
                    collateralTokens.length
                );

            // create new withdrawBuffer target for collateral token
            withdrawBuffer[collateralTokenslength - 1] = WithdrawQueueStorageV1.TokenWithdrawBuffer(
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

        // NOTE: could fuzz operatorDelegatorAllocation for more randomness
        uint256 operatorDelegatorAllocation = 10_000; // 10,000 BP because only using one active OperatorDelegator at a time

        // Add OperatorDelegator and collateral token to RestakeManager
        // NOTE: Removes the previously set OperatorDelegator and collateral token so only one is set at a time
        {
            // only remove previously set values if not first deployment
            if (hasDoneADeploy) {
                // NOTE: this assumes there is only ever one OperatorDelegator in the array, if this isn't true, this logic will be incorrect
                IOperatorDelegator operatorDelegatorToRemove = restakeManager.operatorDelegators(0);
                // remove previously set OperatorDelegator
                restakeManager.removeOperatorDelegator(operatorDelegatorToRemove);

                // remove previously set collateral token
                IERC20 collateralTokenToRemove = restakeManager.collateralTokens(0);
                restakeManager.removeCollateralToken(collateralTokenToRemove);
            }

            // adds most recently deployed OperatorDelegator to RestakeManager
            restakeManager.addOperatorDelegator(
                IOperatorDelegator(address(operatorDelegators[operatorDelegators.length - 1])),
                operatorDelegatorAllocation
            );

            // adds the most recently deployed collateral token to the restake manager
            restakeManager.addCollateralToken(
                IERC20(address(collateralTokens[collateralTokens.length - 1]))
            );

            // sets the active collateral token and OperatorDelegator for access in tests
            activeOperatorDelegator = operatorDelegators[operatorDelegators.length - 1];
            activeCollateralToken = collateralTokens[collateralTokens.length - 1];
        }

        // NOTE: only set this to true here to not interfere with above logic for removing any exsiting OperatorDelegator + token
        if (RECON_USE_SINGLE_DEPLOY) {
            hasDoneADeploy = true;
        }
    }
}
