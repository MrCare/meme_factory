// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Meme} from "./Meme.sol";

contract MinimalProxy {
    address public immutable implementation;
    
    constructor(address _implementation) {
        implementation = _implementation;
    }
    
    function createInscription(
        string memory symbol,
        uint256 maxSupply,
        uint256 perMint
    ) external returns (address) {
        // Create minimal proxy using CREATE2 for deterministic addresses
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        
        bytes32 salt = keccak256(abi.encodePacked(symbol, maxSupply, perMint, block.timestamp));
        address proxy;
        
        assembly {
            proxy := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        
        require(proxy != address(0), "Proxy creation failed");
        
        // Initialize the proxy
        Meme(proxy).initialize(symbol, maxSupply, perMint);
        
        return proxy;
    }
}
