// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {BridgeTokensScript} from "script/BridgeTokens.s.sol";
import {ConfigurePoolScript} from "script/ConfigurePool.s.sol";
import {TokenAndPoolDeployer, VaultDeployer} from "script/Deployer.s.sol";
import {Vault} from "src/Vault.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {CCIPLocalSimulatorFork, Register, IRouterFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

contract InteractionsTest is Test {
    TokenAndPoolDeployer public tokenAndPoolDeployer;
    VaultDeployer public vaultDeployer;

    RebaseToken public rebaseToken;
    RebaseTokenPool public tokenPool;
    Vault public vault;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    Register.NetworkDetails public networkDetails;

    address public DEPLOYER;
    uint256 INITIAL_BALANCE = 100 ether;

    function setUp() public {
        DEPLOYER = makeAddr("deployer");
        vm.deal(DEPLOYER, INITIAL_BALANCE); // ✅ Give deployer ETH, no prank yet

        // Deploy via script (includes vm.startBroadcast internally)
        tokenAndPoolDeployer = new TokenAndPoolDeployer();
        (rebaseToken, tokenPool) = tokenAndPoolDeployer.run();

        vaultDeployer = new VaultDeployer();
        vault = vaultDeployer.run(address(rebaseToken));

        // After deployments, you can use prank in test functions
        // (but not before or during the broadcast calls)

        // Optional: setup simulator for assertions
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    }

    // function testContractsAreDeployed() public {
    //     assert(address(rebaseToken) != address(0));
    //     assert(address(tokenPool) != address(0));
    //     assert(address(vault) != address(0));
    // }

    function testTokenPoolHasMintAndBurnRole() public view {
        bytes32 role = rebaseToken.getMintAndBurnRole();
        assertTrue(rebaseToken.hasRole(role, address(tokenPool)));
    }
}
