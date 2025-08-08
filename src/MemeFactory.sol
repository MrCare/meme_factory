// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Meme} from "./Meme.sol";
import {MinimalProxy} from "./MinimalProxy.sol";

contract MemeFactory {
    address public implementation;
    MinimalProxy public proxy;
    address public owner;
    
    uint256 public constant PLATFORM_FEE_RATE = 100; // 1% = 100 / 10000
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    struct MemeInfo {
        string symbol;
        uint256 maxSupply;
        uint256 perMint;
        uint256 price;
        uint256 minted;
        address creator;
        bool exists;
    }
    
    mapping(address => MemeInfo) public memes;
    mapping(string => address) public symbolToToken;
    address[] public allMemes;
    
    event MemeDeployed(
        address indexed token, 
        string symbol, 
        uint256 maxSupply, 
        uint256 perMint, 
        uint256 price,
        address indexed creator
    );
    event MemeMinted(
        address indexed token, 
        address indexed to, 
        uint256 amount, 
        uint256 paid,
        uint256 platformFee,
        uint256 creatorFee
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        implementation = address(new Meme());
        proxy = new MinimalProxy(implementation);
    }
    
    function deployMeme(
        string memory symbol, 
        uint256 totalSupply, 
        uint256 perMint,
        uint256 price
    ) external returns (address) {
        require(symbolToToken[symbol] == address(0), "Symbol exists");
        require(totalSupply > 0, "Invalid total supply");
        require(perMint > 0 && perMint <= totalSupply, "Invalid per mint");
        
        address newToken = proxy.createMeme(symbol, totalSupply, perMint, price, msg.sender);
        
        memes[newToken] = MemeInfo({
            symbol: symbol,
            maxSupply: totalSupply,
            perMint: perMint,
            price: price,
            minted: 0,
            creator: msg.sender,
            exists: true
        });
        
        symbolToToken[symbol] = newToken;
        allMemes.push(newToken);
        
        emit MemeDeployed(newToken, symbol, totalSupply, perMint, price, msg.sender);
        
        return newToken;
    }
    
    function mintMeme(address tokenAddr) external payable returns (bool) {
        require(memes[tokenAddr].exists, "Meme not exists");
        
        MemeInfo storage memeInfo = memes[tokenAddr];
        uint256 totalCost = memeInfo.price * memeInfo.perMint;
        require(msg.value >= totalCost, "Insufficient payment");
        
        // Calculate fees
        uint256 platformFee = (totalCost * PLATFORM_FEE_RATE) / FEE_DENOMINATOR;
        uint256 creatorFee = totalCost - platformFee;
        
        // Mint tokens
        bool success = Meme(tokenAddr).mint(msg.sender);
        require(success, "Mint failed");
        
        // Get the actual perMint amount from the Meme contract (in wei)
        uint256 actualPerMint = Meme(tokenAddr).perMint();
        
        // Update minted amount
        memeInfo.minted += memeInfo.perMint;
        
        // Transfer fees
        if (platformFee > 0) {
            payable(owner).transfer(platformFee);
        }
        if (creatorFee > 0) {
            payable(memeInfo.creator).transfer(creatorFee);
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit MemeMinted(tokenAddr, msg.sender, actualPerMint, totalCost, platformFee, creatorFee);
        
        return true;
    }
    
    function getMemeInfo(address tokenAddr) external view returns (MemeInfo memory) {
        return memes[tokenAddr];
    }
    
    function getAllMemes() external view returns (address[] memory) {
        return allMemes;
    }
    
    function calculateMintCost(address tokenAddr) external view returns (uint256) {
        require(memes[tokenAddr].exists, "Meme not exists");
        return memes[tokenAddr].price * memes[tokenAddr].perMint;
    }
}
