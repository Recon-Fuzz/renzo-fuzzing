// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { RestakeManagerTargetsV2 } from "./RestakeManagerTargetsV2.sol";
import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";

contract CryticToFoundryV2 is Test, RestakeManagerTargetsV2, FoundryAsserts {
    function setUp() public {
        setup();
    }

    function test_target_deployer_single() public {
        restakeManager_deployTokenStratOperatorDelegator();

        // need to check that values are properly set in RestakeManager after deployment
        console2.log(restakeManager.getOperatorDelegatorsLength());
        console2.log(restakeManager.getCollateralTokensLength());
        assertTrue(
            restakeManager.getOperatorDelegatorsLength() == 1 &&
                restakeManager.getCollateralTokensLength() == 1,
            "initial values for OperatorDelegator and CollateralToken not set"
        );
    }

    // call to deploy shouldn't override set values
    function test_deploy_multi() public {
        restakeManager_deployTokenStratOperatorDelegator();

        restakeManager_deployTokenStratOperatorDelegator();

        // there should be multiple ODs and tokens in the arrays in target but not in RestakeManager
        console2.log("operatorDelegators length: ", operatorDelegators.length);
        console2.log("collateralTokens length: ", collateralTokens.length);
        assertTrue(operatorDelegators.length == 2, "OperatorDelegator not added to possible set");
        assertTrue(collateralTokens.length == 2, "CollateralToken not added to possible set");

        console2.log(
            "RestakeManager operatorDelegators length: ",
            restakeManager.getOperatorDelegatorsLength()
        );
        console2.log(
            "RestakeManager collateralTokens length: ",
            restakeManager.getCollateralTokensLength()
        );
        assertTrue(
            restakeManager.getOperatorDelegatorsLength() == 1,
            "OperatorDelegator added to RestakeManager"
        );
        assertTrue(
            restakeManager.getCollateralTokensLength() == 1,
            "OperatorDelegator added to RestakeManager"
        );
    }

    // only calling deploy then set should switch the values
    function test_deploy_and_set_multi() public {
        // deploy first combo
        restakeManager_deployTokenStratOperatorDelegator();

        console2.log("active operatorDelegator: ", address(restakeManager.operatorDelegators(0)));
        console2.log("active collateralToken: ", address(restakeManager.collateralTokens(0)));

        // deploy second combo
        restakeManager_deployTokenStratOperatorDelegator();

        // switch to second combo as active one
        restakeManager_switchTokenAndDelegator(1, 1);

        console2.log("active operatorDelegator: ", address(restakeManager.operatorDelegators(0)));
        console2.log("active collateralToken: ", address(restakeManager.collateralTokens(0)));
    }
}
