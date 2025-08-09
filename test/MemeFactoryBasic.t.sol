// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MemeFactory.sol";
import "../src/Meme.sol";
import "../src/IERC20.sol";

contract MemeFactoryBasicTest is Test {
    MemeFactory public factory;
    address public owner;
    address public creator;
    address public buyer1;
    address public buyer2;
    
    // Add receive function to accept ETH transfers
    receive() external payable {}
    
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
    
    function setUp() public {
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
    
    function testDeployMeme() public {
        vm.startPrank(creator);
        
        // Test successful deployment
        address token = factory.deployMeme("PEPE", 1000000, 1000, 1e15); // 0.001 ETH per token
        
        assertTrue(token != address(0));
        assertEq(factory.symbolToToken("PEPE"), token);
        
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(token);
        assertEq(info.symbol, "PEPE");
        assertEq(info.maxSupply, 1000000);
        assertEq(info.perMint, 1000);
        assertEq(info.price, 1e15);
        assertEq(info.creator, creator);
        assertTrue(info.exists);
        assertFalse(info.liquidityAdded); // Initially no liquidity
        
        vm.stopPrank();
    }
    
    function testDeployMemeEmitsEvent() public {
        vm.startPrank(creator);
        
        // We can't predict the exact address, but we can check if the event is emitted
        vm.expectEmit(false, true, false, true); // Only check indexed creator and data
        emit MemeDeployed(address(0), "DOGE", 500000, 500, 2e15, creator);
        
        address token = factory.deployMeme("DOGE", 500000, 500, 2e15);
        
        // Verify the token was actually created
        assertTrue(token != address(0));
        
        vm.stopPrank();
    }
    
    function testCannotDeployDuplicateSymbol() public {
        vm.startPrank(creator);
        
        factory.deployMeme("SHIB", 1000000, 1000, 1e15);
        
        vm.expectRevert("Symbol exists");
        factory.deployMeme("SHIB", 2000000, 2000, 2e15);
        
        vm.stopPrank();
    }
    
    function testCannotDeployInvalidParams() public {
        vm.startPrank(creator);
        
        // Invalid total supply
        vm.expectRevert("Invalid total supply");
        factory.deployMeme("INVALID1", 0, 1000, 1e15);
        
        // Invalid per mint (zero)
        vm.expectRevert("Invalid per mint");
        factory.deployMeme("INVALID2", 1000000, 0, 1e15);
        
        // Invalid per mint (exceeds total supply)
        vm.expectRevert("Invalid per mint");
        factory.deployMeme("INVALID3", 1000, 2000, 1e15);
        
        vm.stopPrank();
    }
    
    function testCalculateMintCost() public {
        vm.prank(creator);
        address token = factory.deployMeme("COST", 1000000, 1000, 1e15);
        
        uint256 cost = factory.calculateMintCost(token);
        assertEq(cost, 1e15 * 1000); // price * perMint
    }
    
    function testGetMemeInfo() public {
        vm.prank(creator);
        address token = factory.deployMeme("INFO", 500000, 500, 2e15);
        
        MemeFactory.MemeInfo memory info = factory.getMemeInfo(token);
        assertEq(info.symbol, "INFO");
        assertEq(info.maxSupply, 500000);
        assertEq(info.perMint, 500);
        assertEq(info.price, 2e15);
        assertEq(info.creator, creator);
        assertEq(info.minted, 0);
        assertTrue(info.exists);
        assertFalse(info.liquidityAdded);
    }
    
    function testGetAllMemes() public {
        vm.startPrank(creator);
        
        address token1 = factory.deployMeme("TOKEN1", 1000000, 1000, 1e15);
        address token2 = factory.deployMeme("TOKEN2", 2000000, 2000, 2e15);
        
        address[] memory allMemes = factory.getAllMemes();
        assertEq(allMemes.length, 2);
        assertEq(allMemes[0], token1);
        assertEq(allMemes[1], token2);
        
        vm.stopPrank();
    }
    
    function testCannotMintNonexistentMeme() public {
        address fakeToken = address(0x1234);
        
        vm.prank(buyer1);
        vm.expectRevert("Meme not exists");
        factory.mintMeme{value: 1 ether}(fakeToken);
    }
    
    function testCannotMintInsufficientPayment() public {
        vm.prank(creator);
        address token = factory.deployMeme("INSUF", 1000000, 1000, 1e15);
        
        uint256 cost = 1e15 * 1000;
        uint256 insufficientPayment = cost - 1;
        
        vm.prank(buyer1);
        vm.expectRevert("Insufficient payment");
        factory.mintMeme{value: insufficientPayment}(token);
    }
}
