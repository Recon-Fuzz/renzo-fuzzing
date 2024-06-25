// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { EigenLayerSystem } from "eigenlayer/test/recon/EigenLayerSystem.sol";
import { vm } from "@chimera/Hevm.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "test/helpers/ProxyAdmin.sol";
import "contracts/Permissions/RoleManager.sol";
import "contracts/token/EzEthToken.sol";
import "contracts/Oracle/RenzoOracle.sol";
import "contracts/Deposits/DepositQueue.sol";
import "contracts/RestakeManager.sol";
import "contracts/Withdraw/WithdrawQueue.sol";
import "contracts/Withdraw/WithdrawQueueStorage.sol";
import "contracts/Rewards/RewardHandler.sol";
import "contracts/Delegation/OperatorDelegator.sol";
import "test/mocks/MockERC20.sol";
import "test/mocks/MockAggregatorV3.sol";
import "forge-std/console2.sol";

contract RenzoSetupV2 is EigenLayerSystem {
    // EigenLayerSetup sets the admin address using this
    // address admin = address(this);

    ProxyAdmin internal renzoProxyAdmin;
    RoleManager internal roleManager;
    RoleManager internal roleManagerImplementation;
    EzEthToken internal ezETH;
    EzEthToken internal ezETHImplementation;
    RenzoOracle internal renzoOracle;
    RenzoOracle internal renzoOracleImplementation;
    MockAggregatorV3 internal stEthPriceOracle;
    MockAggregatorV3 internal wbEthPriceOracle;
    DepositQueue internal depositQueue;
    DepositQueue internal depositQueueImplementation;
    RestakeManager internal restakeManager;
    RestakeManager internal restakeManagerImplementation;
    WithdrawQueue internal withdrawQueue;
    WithdrawQueue internal withdrawQueueImplementation;
    RewardHandler internal rewardHandler;
    RewardHandler internal rewardHandlerImplementation;
    OperatorDelegator internal operatorDelegatorImplementation;
    OperatorDelegator[] internal operatorDelegators;
    OperatorDelegator internal operatorDelegator1;
    OperatorDelegator internal operatorDelegator2;
    address[] internal collateralTokens;

    mapping(address => MockAggregatorV3) internal collateralTokenOracles;

    function deployRenzo() internal {
        renzoProxyAdmin = new ProxyAdmin();

        // deploy RoleManager proxy
        roleManagerImplementation = new RoleManager();
        roleManager = RoleManager(
            address(
                new TransparentUpgradeableProxy(
                    address(roleManagerImplementation),
                    address(renzoProxyAdmin),
                    ""
                )
            )
        );
        // initialize with admin as roleManagerAdmin
        roleManager.initialize(admin);
        roleManager.grantRole(roleManager.RESTAKE_MANAGER_ADMIN(), admin);
        roleManager.grantRole(roleManager.NATIVE_ETH_RESTAKE_ADMIN(), admin);
        roleManager.grantRole(roleManager.OPERATOR_DELEGATOR_ADMIN(), admin);
        roleManager.grantRole(roleManager.ORACLE_ADMIN(), admin);
        roleManager.grantRole(roleManager.RESTAKE_MANAGER_ADMIN(), admin);
        roleManager.grantRole(roleManager.ERC20_REWARD_ADMIN(), admin);
        roleManager.grantRole(roleManager.WITHDRAW_QUEUE_ADMIN(), admin);
        roleManager.grantRole(roleManager.DEPOSIT_WITHDRAW_PAUSER(), admin);

        // deploy tokens
        ezETHImplementation = new EzEthToken();
        ezETH = EzEthToken(
            address(
                new TransparentUpgradeableProxy(
                    address(ezETHImplementation),
                    address(renzoProxyAdmin),
                    ""
                )
            )
        );
        ezETH.initialize(roleManager);

        // deploy oracle, needs to be done as a proxy
        renzoOracleImplementation = new RenzoOracle();
        renzoOracle = RenzoOracle(
            address(
                new TransparentUpgradeableProxy(
                    address(renzoOracleImplementation),
                    address(renzoProxyAdmin),
                    ""
                )
            )
        );
        renzoOracle.initialize(roleManager);

        // deploy the EigenLayer system
        deployEigenLayerLocal();

        vm.warp(1524785992); // warps to echidna's initial start time
        stEthPriceOracle = new MockAggregatorV3(
            18, // decimals
            "stETH price oracle", // description
            1, // version
            1e18, // answer
            block.timestamp, // startedAt
            block.timestamp // updatedAt
        );
        wbEthPriceOracle = new MockAggregatorV3(
            18,
            "wbETH price oracle",
            1,
            11e18 / 10,
            block.timestamp,
            block.timestamp
        );

        renzoOracle.setOracleAddress(
            IERC20(address(stETH)),
            AggregatorV3Interface(address(stEthPriceOracle))
        );
        renzoOracle.setOracleAddress(
            IERC20(address(wbETH)),
            AggregatorV3Interface(address(wbEthPriceOracle))
        );

        // mint tokens to test contract
        stETH.mint(address(this), 10_000_000);
        wbETH.mint(address(this), 10_000_000);

        collateralTokens.push(address(stETH));
        collateralTokens.push(address(wbETH));

        // deploy DepositQueue
        depositQueueImplementation = new DepositQueue();
        depositQueue = DepositQueue(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(depositQueueImplementation),
                        address(renzoProxyAdmin),
                        ""
                    )
                )
            )
        );
        depositQueue.initialize(roleManager);

        // deploy RestakeManager
        restakeManagerImplementation = new RestakeManager();
        restakeManager = RestakeManager(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(restakeManagerImplementation),
                        address(renzoProxyAdmin),
                        ""
                    )
                )
            )
        );
        restakeManager.initialize(
            roleManager,
            ezETH,
            renzoOracle,
            IStrategyManager(address(strategyManager)),
            IDelegationManager(address(delegation)),
            depositQueue
        );

        stETH.approve(address(restakeManager), type(uint256).max);
        wbETH.approve(address(restakeManager), type(uint256).max);

        // deploy WithdrawQueue
        withdrawQueueImplementation = new WithdrawQueue();
        withdrawQueue = WithdrawQueue(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(withdrawQueueImplementation),
                        address(renzoProxyAdmin),
                        ""
                    )
                )
            )
        );

        // initializing this with an empty buffer array, tokens are added to withdrawBuffer in deployTokenStratOperatorDelegator
        WithdrawQueueStorageV1.TokenWithdrawBuffer[]
            memory withdrawBuffer = new WithdrawQueueStorageV1.TokenWithdrawBuffer[](1);
        // NOTE: adding ezETH to withdraw buffer array because it can't be used for initialization if array is empty
        withdrawBuffer[0] = WithdrawQueueStorageV1.TokenWithdrawBuffer(address(ezETH), 10_000);

        withdrawQueue.initialize(
            roleManager,
            restakeManager,
            ezETH,
            renzoOracle,
            7 days,
            withdrawBuffer
        );

        // set WithdrawQueue in DepositQueue
        depositQueue.setWithdrawQueue(IWithdrawQueue(address(withdrawQueue)));
        // set RestakeManager in DepositQueue
        depositQueue.setRestakeManager(IRestakeManager(address(restakeManager)));
        // Allow the restake manager to mint and burn ezETH tokens
        roleManager.grantRole(roleManager.RX_ETH_MINTER_BURNER(), address(restakeManager));

        // deploy the RewardHandler
        rewardHandlerImplementation = new RewardHandler();
        rewardHandler = RewardHandler(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(rewardHandlerImplementation),
                        address(renzoProxyAdmin),
                        ""
                    )
                )
            )
        );
        rewardHandler.initialize(roleManager, address(depositQueue));

        // deploy OperatorDelegators
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

        operatorDelegator2 = OperatorDelegator(
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
        operatorDelegator2.initialize(
            roleManager,
            IStrategyManager(address(strategyManager)),
            restakeManager,
            IDelegationManager(address(delegation)),
            IEigenPodManager(address(eigenPodManager))
        );

        // set token strategies on OperatorDelegators
        operatorDelegator1.setTokenStrategy(
            IERC20(address(stETH)),
            IStrategy(address(deployedStrategyArray[0]))
        );
        operatorDelegator1.setTokenStrategy(
            IERC20(address(wbETH)),
            IStrategy(address(deployedStrategyArray[1]))
        );
        operatorDelegator2.setTokenStrategy(
            IERC20(address(stETH)),
            IStrategy(address(deployedStrategyArray[0]))
        );
        operatorDelegator2.setTokenStrategy(
            IERC20(address(wbETH)),
            IStrategy(address(deployedStrategyArray[1]))
        );
        operatorDelegators.push(operatorDelegator1);
        operatorDelegators.push(operatorDelegator2);

        // add operator delegators to RestakeManager
        restakeManager.addOperatorDelegator(
            IOperatorDelegator(address(operatorDelegator1)),
            7000 // 70% to operator 1
        );
        restakeManager.addOperatorDelegator(
            IOperatorDelegator(address(operatorDelegator2)),
            3000 // 30% to operator 2
        );

        // add the collateral tokens to the restake manager
        restakeManager.addCollateralToken(IERC20(address(stETH)));
        restakeManager.addCollateralToken(IERC20(address(wbETH)));
    }

    /** Utils **/
    function _getRandomDepositableToken(uint256 tokenIndex) internal view returns (address) {
        return collateralTokens[tokenIndex % collateralTokens.length];
    }

    function _getRandomOperatorDelegator(
        uint256 operatorDelegatorIndex
    ) internal view returns (IOperatorDelegator operatorDelegator) {
        return operatorDelegators[operatorDelegatorIndex % operatorDelegators.length];
    }
}
