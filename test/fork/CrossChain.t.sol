// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register, IRouterFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainTest is Test {
    address OWNER = makeAddr("owner");
    address USER = makeAddr("user");
    uint256 SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        // 1. Create and select the initial (source) fork (Sepolia)
        // This uses the "sepolia" alias defined in foundry.toml
        sepoliaFork = vm.createSelectFork("sepolia");

        // 2. Create the destination fork (Arbitrum Sepolia) but don't select it yet
        // This uses the "arb-sepolia" alias defined in foundry.toml
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // 3. Deploy the CCIP Local Simulator contract
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // 4. Make the simulator's address persistent across all active forks
        // This is crucial so both the Sepolia and Arbitrum Sepolia forks
        // can interact with the *same* instance of the simulator.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 5. Deploy and configure the RebaseToken and RebaseTokenPool contracts on Sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // ccipLocalSimulatorFork.setNetworkDetails(block.chainid, sepoliaNetworkDetails);
        vm.startPrank(OWNER);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)), // Cast token via address
            new address[](0), // Empty allowlist
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        // 6. Deploy and configure the RebaseToken and RebaseTokenPool contracts on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        // ccipLocalSimulatorFork.setNetworkDetails(block.chainid, arbSepoliaNetworkDetails);
        vm.startPrank(OWNER);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)), // Cast token via address
            new address[](0), // Empty allowlist
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();
        configureTokenPool(
            sepoliaFork, // Local chain: Sepolia
            address(sepoliaPool), // Local pool: Sepolia's TokenPool
            arbSepoliaNetworkDetails.chainSelector, // Remote chain selector: Arbitrum Sepolia's
            address(arbSepoliaPool), // Remote pool address: Arbitrum Sepolia's TokenPool
            address(arbSepoliaToken) // Remote token address: Arbitrum Sepolia's Token
        );
        configureTokenPool(
            arbSepoliaFork, // Local chain: Arbitrum Sepolia
            address(arbSepoliaPool), // Local pool: Arbitrum Sepolia's TokenPool
            sepoliaNetworkDetails.chainSelector, // Remote chain selector: Sepolia's
            address(sepoliaPool), // Remote pool address: Sepolia's TokenPool
            address(sepoliaToken) // Remote token address: Sepolia's Token
        );
    }

    ///////////////////////
    //Helper Functions ////
    ///////////////////////
    function configureTokenPool(
        uint256 forkId, // The fork ID of the local chain
        address localPoolAddress, // Address of the pool being configured
        uint64 remoteChainSelector, // Chain selector of the remote chain
        address remotePoolAddress, // Address of the pool on the remote chain
        address remoteTokenAddress // Address of the token on the remote chain
    ) public {
        // 1. Select the correct fork (local chain context)
        vm.selectFork(forkId);

        // 2. Prepare arguments for applyChainUpdates
        // An empty array as we are only adding, not removing.
        // uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);

        // Construct the chainsToAdd array (with one ChainUpdate struct)
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        // The remote pool address needs to be ABI-encoded as bytes.
        // CCIP expects an array of remote pool addresses, even if there's just one primary.
        // bytes[] memory remotePoolAddressesBytesArray = new bytes[](1);
        // remotePoolAddressesBytesArray[0] = abi.encode(remotePoolAddress);
        bytes memory encodedRemotePoolAddress = abi.encode(remotePoolAddress);

        // Populate the ChainUpdate struct
        // Refer to TokenPool.sol for the ChainUpdate struct definition:
        // struct ChainUpdate {
        // uint64 remoteChainSelector; // ──╮ Remote chain selector
        // bool allowed; // ────────────────╯ Whether the chain should be enabled
        // bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        // bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
        // RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        // RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        // }
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true, // Enable the chain
            remotePoolAddress: encodedRemotePoolAddress, // ABI-encode the array of bytes
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            // For this example, rate limits are disabled.
            // Consult CCIP documentation for production rate limit configurations.
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        // 3. Execute applyChainUpdates as the owner
        // applyChainUpdates is typically an owner-restricted function.
        vm.prank(OWNER); // The 'owner' variable should be the deployer/owner of the localPoolAddress
        TokenPool(localPoolAddress).applyChainUpdates( /*remoteChainSelectorsToRemove,*/ chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);
        vm.startPrank(USER);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(USER), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: "", // We don't need any extra args for this example
            feeToken: localNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            USER, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );
        vm.startPrank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Approve the fee
        // log the values before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(USER);
        console.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(USER);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        vm.selectFork(remoteFork); // switch to remote fork so we can warp the time and get the balance
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(USER);
        console.log("Remote balance before bridge: %d", initialArbBalance);
        vm.selectFork(localFork); // the switchChainAndRouteMessage function assumes you are on the local fork
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        console.log("Remote user interest rate: %d", remoteToken.getUserInterestRate(USER));
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(USER);
        console.log("Remote balance after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    /////////////////////////
    //BridgeTokens Tests ////
    /////////////////////////
    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(USER, SEND_VALUE);
        vm.prank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(USER), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbSepoliaToken.balanceOf(USER),
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }
}
