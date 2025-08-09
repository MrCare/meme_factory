// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MemeFactory.sol";
import "../src/Meme.sol";
import "../src/IERC20.sol";

contract MemeFactoryWithTWAPTest is Test {
    MemeFactory public factory;
    address public owner;
    address public creator;
    address public buyer1;
    address public buyer2;
    
    // Fork Sepolia for testing
    uint256 sepoliaFork;
    
    // Add receive function to accept ETH transfers
    receive() external payable {}
    
    function setUp() public {
        // Fork Sepolia using environment variable
        string memory sepoliaRpc = vm.envString("SEPOLIA_RPC");
        sepoliaFork = vm.createFork(sepoliaRpc);
        vm.selectFork(sepoliaFork);
        
        owner = address(this);
        creator = makeAddr("creator");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        
        factory = new MemeFactory();
        
        // Give test accounts some ETH
        vm.deal(creator, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
    }
    
    function testDeployMemeWithLiquidity() public {
        vm.prank(creator);
        address token = factory.deployMeme("PEPE", 1000000, 1000, 1e15); // 0.001 ETH per token
        
        assertTrue(token != address(0));
        
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(token);
        assertEq(info.symbol, "PEPE");
        assertEq(info.maxSupply, 1000000);
        assertEq(info.perMint, 1000);
        assertEq(info.price, 1e15);
        assertEq(info.creator, creator);
        assertTrue(info.exists);
        assertFalse(info.liquidityAdded); // No liquidity yet
    }
    
    function testMintMemeAddsLiquidity() public {
        // Deploy meme
        vm.prank(creator);
        address token = factory.deployMeme("LIQUIDITY", 1000000, 1000, 1e15);
        
        uint256 cost = factory.calculateMintCost(token);
        assertEq(cost, 1e15 * 1000); // 1 ETH
        
        uint256 creatorBalanceBefore = creator.balance;
        
        // Mint tokens - this should add liquidity
        vm.prank(buyer1);
        factory.mintMeme{value: cost}(token);
        
        // Check that liquidity was added
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(token);
        assertTrue(info.liquidityAdded);
        
        // Check creator received 95% of payment
        uint256 expectedCreatorFee = cost * 9500 / 10000; // 95%
        assertEq(creator.balance - creatorBalanceBefore, expectedCreatorFee);
        
        // Check user received tokens
        assertEq(IERC20(token).balanceOf(buyer1), 1000 * 1e18);
    }
    
    function testBuyMemeChoosesBestPrice() public {
        // Deploy and mint once to create liquidity
        vm.prank(creator);
        address token = factory.deployMeme("BESTPRICE", 1000000, 1000, 1e15);
        
        uint256 cost = 1e15 * 1000;
        
        // First mint to create liquidity
        vm.prank(buyer1);
        factory.mintMeme{value: cost}(token);
        
        // Check price info
        (uint256 mintPrice, uint256 uniswapPrice, bool shouldUseMint, bool canMint) = 
            factory.getPriceInfo(token, cost);
        
        console.log("Mint price:", mintPrice);
        console.log("Uniswap price:", uniswapPrice);
        console.log("Should use mint:", shouldUseMint);
        console.log("Can mint:", canMint);
        
        // Try buying - should choose the best option
        vm.prank(buyer2);
        factory.buyMeme{value: cost}(token);
        
        // Verify buyer2 received tokens
        uint256 buyer2Balance = IERC20(token).balanceOf(buyer2);
        assertTrue(buyer2Balance > 0);
        console.log("Buyer2 balance:", buyer2Balance);
    }
    
    function testTWAPOracle() public {
        vm.prank(creator);
        address token = factory.deployMeme("TWAP", 1000000, 1000, 1e15);
        
        // Mint to create liquidity
        vm.prank(buyer1);
        factory.mintMeme{value: 1e15 * 1000}(token);
        
        // Check if we can update TWAP
        bool canUpdate = factory.canUpdateTWAP(token);
        console.log("Can update TWAP:", canUpdate);
        
        if (canUpdate) {
            factory.updateTWAP(token);
        }
        
        // Wait some time and try again
        vm.warp(block.timestamp + 301); // Wait 5+ minutes
        
        bool canUpdateAfter = factory.canUpdateTWAP(token);
        console.log("Can update TWAP after wait:", canUpdateAfter);
    }
    
    function testMultipleBuysWithDifferentSources() public {
        vm.prank(creator);
        address token = factory.deployMeme("MULTIBUY", 10000, 1000, 1e15);
        
        uint256 cost = 1e15 * 1000;
        
        // Multiple buyers
        for (uint i = 0; i < 5; i++) {
            address buyer = makeAddr(string(abi.encodePacked("buyer", i)));
            vm.deal(buyer, 10 ether);
            
            vm.prank(buyer);
            factory.buyMeme{value: cost}(token);
            
            console.log("Buyer", i, "balance:", IERC20(token).balanceOf(buyer));
        }
        
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(token);
        console.log("Total minted:", info.minted);
        console.log("Liquidity added:", info.liquidityAdded);
    }
}
