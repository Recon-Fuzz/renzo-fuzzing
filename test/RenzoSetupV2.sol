// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import { Test } from "forge-std/Test.sol";
import { EigenLayerSetupV2 } from "eigenlayer/test/recon/EigenLayerSetupV2.sol";
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

contract RenzoSetupV2 is EigenLayerSetupV2 {
    // EigenLayerSetup sets the admin address using this
    // address admin = address(this);

    ProxyAdmin internal renzoProxyAdmin;
    RoleManager internal roleManager;
    RoleManager internal roleManagerImplementation;
    EzEthToken internal ezETH;
    EzEthToken internal ezETHImplementation;
    RenzoOracle internal renzoOracle;
    RenzoOracle internal renzoOracleImplementation;
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
    MockERC20[] internal collateralTokens;

    mapping(address => MockAggregatorV3) internal collateralTokenOracles;

    function deployRenzo(bool eigenLayerLocal) internal {
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

        address[] memory strategyArray = new address[](2);
        strategyArray[0] = address(0x54945180dB7943c0ed0FEE7EdaB2Bd24620256bc);
        strategyArray[1] = address(0x93c4b944D05dfe6df7645A86cd2206016c51564D);

        if (eigenLayerLocal) {
            // NOTE: modified in V2 to take no tokens as input, strategies instead are deployed by fuzzer
            deployEigenLayerLocal();
        } else {
            // this takes in the strategies used by Renzo to expose their interfaces using EigenLayer contracts
            // TODO: resolve array index out of bounds error when using this
            deployEigenLayerForked(strategyArray);
        }

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
    }

    /** Utils **/
    function _getRandomDepositableToken(uint256 tokenIndex) internal view returns (address) {
        return address(collateralTokens[tokenIndex % collateralTokens.length]);
    }

    // TODO: need to refactor this to work with OperatorDelegator array defined in RestakeManagerTargetsV2
    function _getRandomOperatorDelegator(
        uint256 operatorDelegatorIndex
    ) internal view returns (IOperatorDelegator operatorDelegator) {
        return operatorDelegators[operatorDelegatorIndex % operatorDelegators.length];
    }
}
