// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Meme} from "./Meme.sol";
import {MinimalProxy} from "./MinimalProxy.sol";

contract MemeFactory {
    address public implementation;
    MinimalProxy public proxy;
    address public owner;
    
    struct InscriptionInfo {
        string symbol;
        uint256 maxSupply;
        uint256 perMint;
        uint256 minted;
        bool exists;
    }
    
    mapping(address => InscriptionInfo) public inscriptions;
    mapping(string => address) public symbolToToken;
    address[] public allInscriptions;
    
    event InscriptionDeployed(address indexed token, string symbol, uint256 maxSupply, uint256 perMint);
    event InscriptionMinted(address indexed token, address indexed to, uint256 amount);
    event ImplementationUpgraded(address oldImpl, address newImpl);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        implementation = address(new Meme());
        proxy = new MinimalProxy(implementation);
    }
    
    function deployInscription(
        string memory symbol, 
        uint256 totalSupply, 
        uint256 perMint
    ) external returns (address) {
        require(symbolToToken[symbol] == address(0), "Symbol exists");
        
        address newToken = proxy.createInscription(symbol, totalSupply, perMint);
        
        inscriptions[newToken] = InscriptionInfo({
            symbol: symbol,
            maxSupply: totalSupply,
            perMint: perMint,
            minted: 0,
            exists: true
        });
        
        symbolToToken[symbol] = newToken;
        allInscriptions.push(newToken);
        
        emit InscriptionDeployed(newToken, symbol, totalSupply, perMint);
        
        return newToken;
    }
    
    function mintInscription(address tokenAddr) external returns (bool) {
        require(inscriptions[tokenAddr].exists, "Token not exists");
        
        bool success = Meme(tokenAddr).mint(msg.sender);
        require(success, "Mint failed");
        
        inscriptions[tokenAddr].minted += inscriptions[tokenAddr].perMint;
        
        emit InscriptionMinted(tokenAddr, msg.sender, inscriptions[tokenAddr].perMint);
        
        return true;
    }
    
    function upgradeImplementation(address newImplementation) external onlyOwner {
        address oldImpl = implementation;
        implementation = newImplementation;
        proxy = new MinimalProxy(newImplementation);
        
        emit ImplementationUpgraded(oldImpl, newImplementation);
    }
    
    function getInscriptionInfo(address tokenAddr) external view returns (InscriptionInfo memory) {
        return inscriptions[tokenAddr];
    }
    
    function getAllInscriptions() external view returns (address[] memory) {
        return allInscriptions;
    }
}
