// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import { Test } from "forge-std/Test.sol";
import { EigenLayerSetup } from "eigenlayer/test/recon/EigenLayerSetup.sol";
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

contract SharedSetup is EigenLayerSetup {
    // EigenLayerSetup sets the admin address using this
    // address admin = address(this);

    ProxyAdmin public renzoProxyAdmin;
    RoleManager public roleManager;
    RoleManager public roleManagerImplementation;
    EzEthToken public ezETH;
    EzEthToken public ezETHImplementation;
    MockERC20 public stETH;
    MockERC20 public cbETH;
    RenzoOracle public renzoOracle;
    RenzoOracle public renzoOracleImplementation;
    MockAggregatorV3 public stEthPriceOracle;
    MockAggregatorV3 public cbEthPriceOracle;
    DepositQueue public depositQueue;
    DepositQueue public depositQueueImplementation;
    RestakeManager public restakeManager;
    RestakeManager public restakeManagerImplementation;
    WithdrawQueue public withdrawQueue;
    WithdrawQueue public withdrawQueueImplementation;
    RewardHandler public rewardHandler;
    RewardHandler public rewardHandlerImplementation;
    OperatorDelegator public operatorDelegator1;
    OperatorDelegator public operatorDelegator2;
    OperatorDelegator public operatorDelegatorImplementation;

    function setUp() public {
        renzoProxyAdmin = new ProxyAdmin();

        // deploy RoleManager proxy
        roleManagerImplementation = new RoleManager();
        // this wraps the proxy with the RoleManager interface
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
        roleManager.grantRole(roleManager.OPERATOR_DELEGATOR_ADMIN(), admin);
        roleManager.grantRole(roleManager.ORACLE_ADMIN(), admin);
        roleManager.grantRole(roleManager.RESTAKE_MANAGER_ADMIN(), admin);

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
        stETH = new MockERC20("Staked ETH", "stETH", 18);
        cbETH = new MockERC20("Coinbase ETH", "cbETH", 18);

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

        stEthPriceOracle = new MockAggregatorV3(
            18, // decimals
            "stETH price oracle", // description
            1, // version
            1e18, // answer
            block.timestamp, // startedAt
            block.timestamp // updatedAt
        );
        cbEthPriceOracle = new MockAggregatorV3(
            18,
            "cbETH price oracle",
            1,
            11e18 / 10,
            block.timestamp,
            block.timestamp
        );

        renzoOracle.setOracleAddress(stETH, AggregatorV3Interface(address(stEthPriceOracle)));
        renzoOracle.setOracleAddress(cbETH, AggregatorV3Interface(address(cbEthPriceOracle)));

        // deploy EigenLayer to be able to access StrategyManager and DelegationManager
        // @audit need to change this to use the new function interface
        address[] memory lstAddresses = new address[](2);
        lstAddresses[0] = address(stETH);
        lstAddresses[1] = address(cbETH);
        deployEigenLayer(lstAddresses);

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
        WithdrawQueueStorageV1.TokenWithdrawBuffer[]
            memory withdrawBuffer = new WithdrawQueueStorageV1.TokenWithdrawBuffer[](2);
        withdrawBuffer[0] = WithdrawQueueStorageV1.TokenWithdrawBuffer(address(stETH), 10_000);
        withdrawBuffer[1] = WithdrawQueueStorageV1.TokenWithdrawBuffer(address(cbETH), 10_000);

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

        // @audit stopped here
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
            IERC20(address(cbETH)),
            IStrategy(address(deployedStrategyArray[1]))
        );
        operatorDelegator2.setTokenStrategy(
            IERC20(address(stETH)),
            IStrategy(address(deployedStrategyArray[0]))
        );
        operatorDelegator2.setTokenStrategy(
            IERC20(address(cbETH)),
            IStrategy(address(deployedStrategyArray[1]))
        );

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
        restakeManager.addCollateralToken(IERC20(address(cbETH)));
    }
}
