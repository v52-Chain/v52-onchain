// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {V52EvidenceRegistry} from "../contracts/hsk/V52EvidenceRegistry.sol";

/// @notice Deploys V52EvidenceRegistry to HSK (mainnet or testnet).
///
/// Required environment variables:
///   PRIVATE_KEY        - deployer/issuer key, 0x-prefixed (funds gas + becomes the initial issuer)
///
/// Optional environment variables:
///   INITIAL_ISSUER     - address to allow-list as issuer at deploy time.
///                        Defaults to the deployer address derived from PRIVATE_KEY.
///
/// Usage (HSK testnet, chain id 133):
///   forge script script/DeployV52EvidenceRegistry.s.sol:DeployV52EvidenceRegistry \
///     --rpc-url hsk_testnet --broadcast -vvvv
contract DeployV52EvidenceRegistry is Script {
    function run() external returns (V52EvidenceRegistry registry) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address initialIssuer = vm.envOr("INITIAL_ISSUER", deployer);

        console2.log("Deployer / owner :", deployer);
        console2.log("Initial issuer   :", initialIssuer);
        console2.log("Chain id         :", block.chainid);

        vm.startBroadcast(deployerKey);
        registry = new V52EvidenceRegistry(initialIssuer);
        vm.stopBroadcast();

        console2.log("V52EvidenceRegistry deployed at:", address(registry));
    }
}
