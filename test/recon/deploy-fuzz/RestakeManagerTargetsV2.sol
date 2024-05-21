// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { BaseTargetFunctions } from "@chimera/BaseTargetFunctions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { vm } from "@chimera/Hevm.sol";

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
import "../../mocks/MockAggregatorV3.sol";
import { WithdrawQueue } from "contracts/Withdraw/WithdrawQueue.sol";
import { WithdrawQueueStorageV1 } from "contracts/Withdraw/WithdrawQueueStorage.sol";

// TODO: include setPrice for aggregator in different contract
abstract contract RestakeManagerTargetsV2 is BaseTargetFunctions, DepositQueueTargetsV2 {
    bool internal hasDoneADeploy;
    uint8 internal decimals;
    uint256 internal initialMintPerUsers;
    MockERC20 internal collateralToken1;
    MockAggregatorV3 internal collateralToken1Oracle;
    // StrategyBaseTVLLimits[] internal deployedStrategyArray;
    // strategies deployed
    IStrategy[] internal deployedStrategyArray;

    // MockAggregatorV3 internal collateralToken1Oracle;
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

        if (RECON_USE_SINGLE_DEPLOY) {
            hasDoneADeploy = true;
        }

        if (RECON_USE_HARDCODED_DECIMALS) {
            decimals = 18;
        }

        initialMintPerUsers = 1_000_000e18;

        // deploy collateral token
        collateralToken1 = new MockERC20("Collateral Token 1", "CT1", decimals);
        collateralToken1.mint(address(this), initialMintPerUsers);
        collateralToken1.approve(address(restakeManager), type(uint256).max);

        // deploy collateral token oracle
        vm.warp(1524785992); // warps to echidna's initial start time
        collateralToken1Oracle = new MockAggregatorV3(
            18, // decimals
            "CT1 price oracle", // description
            1, // version
            1e18, // answer
            block.timestamp, // startedAt
            block.timestamp // updatedAt
        );

        renzoOracle.setOracleAddress(
            collateralToken1,
            AggregatorV3Interface(address(collateralToken1Oracle))
        );

        lstAddresses.push(address(collateralToken1));

        // deploy EL strategy for token
        baseStrategyImplementation = new StrategyBaseTVLLimits(strategyManager);
        for (uint256 i = 0; i < lstAddresses.length; ++i) {
            deployedStrategyArray.push(
                IStrategy(
                    address(
                        StrategyBaseTVLLimits(
                            address(
                                new TransparentUpgradeableProxy(
                                    address(baseStrategyImplementation),
                                    address(eigenLayerProxyAdmin),
                                    abi.encodeWithSelector(
                                        StrategyBaseTVLLimits.initialize.selector,
                                        type(uint256).max,
                                        type(uint256).max,
                                        IERC20(lstAddresses[i]),
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
        bool[] memory thirdPartyTransfers = new bool[](deployedStrategyArray.length); // default to allowing third party transfers
        // Create a memory array with the same length as the storage array
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](deployedStrategyArray.length);

        // Copy elements from the storage array to the memory array
        for (uint i = 0; i < deployedStrategyArray.length; i++) {
            strategiesToWhitelist[i] = deployedStrategyArray[i];
        }
        strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist, thirdPartyTransfers);

        // set collateral token in WithdrawQueue
        WithdrawQueueStorageV1.TokenWithdrawBuffer[]
            memory withdrawBuffer = new WithdrawQueueStorageV1.TokenWithdrawBuffer[](
                lstAddresses.length
            );
        withdrawBuffer[0] = WithdrawQueueStorageV1.TokenWithdrawBuffer(
            address(collateralToken1),
            10_000
        );

        // initialize the withdrawQueue with collateralToken1 buffer
        // NOTE: buffers can be added using the updateWithdrawBufferTarget function

        // deploy OperatorDelegator and set the token for it
        operatorDelegatorImplementation = new OperatorDelegator();
        operatorDelegator1 = OperatorDelegator(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(operatorDelegatorImplementation),
                        address(renzoProxyAdmin),
                        ""
                    )
                )
            )
        );
        operatorDelegator1.initialize(
            roleManager,
            IStrategyManager(address(strategyManager)),
            restakeManager,
            IDelegationManager(address(delegation)),
            IEigenPodManager(address(eigenPodManager))
        );
    }
}
