// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/CliffWallet.sol";
import "../src/IERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    
    constructor(uint256 _supply) {
        _totalSupply = _supply;
        _balances[msg.sender] = _supply;
    }
    
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        return true;
    }
}

contract CliffWalletTest is Test {
    CliffWallet public wallet;
    MockERC20 public token;
    
    address public beneficiary = address(0x1);
    address public deployer = address(this);
    
    uint256 constant CLIFF = 365 days; // 12 months
    uint256 constant VESTING = 730 days; // 24 months
    uint256 constant TOTAL = 1_000_000e18; // 1M tokens
    
    function setUp() public {
        // Deploy mock token with enough supply
        token = new MockERC20(10_000_000e18);
        
        // Calculate the future address of the wallet contract using CREATE2 or
        // use a different approach: deploy first, then fund separately
        
        // Method 1: Use vm.computeCreateAddress to predict the wallet address
        address futureWallet = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        
        // Approve the future wallet address
        token.approve(futureWallet, TOTAL);
        
        // Deploy wallet - now it can call transferFrom successfully
        wallet = new CliffWallet(beneficiary, address(token));
        
        // Verify the predicted address was correct
        require(address(wallet) == futureWallet, "Address prediction failed");
    }
    
    function test_Constructor() public view {
        assertEq(wallet.beneficiary(), beneficiary);
        assertEq(address(wallet.token()), address(token));
        assertEq(wallet.startTime(), block.timestamp);
        assertEq(wallet.released(), 0);
        assertEq(token.balanceOf(address(wallet)), TOTAL);
    }
    
    function test_ReleasableBeforeCliff() public {
        uint256 startTime = wallet.startTime();
        
        // Should be 0 before cliff
        assertEq(wallet.releasable(), 0);
        
        // Move forward but still before cliff (10 months from start)
        vm.warp(startTime + 300 days);
        assertEq(wallet.releasable(), 0);
        
        // Just before cliff ends
        vm.warp(startTime + CLIFF - 1);
        assertEq(wallet.releasable(), 0);
    }
    
    function test_ReleaseFailsBeforeCliff() public {
        vm.expectRevert("Nothing to release");
        wallet.release();
        
        // Move to just before cliff ends
        vm.warp(block.timestamp + CLIFF - 1);
        vm.expectRevert("Nothing to release");
        wallet.release();
    }
    
    function test_ReleasableAfterCliff() public {
        uint256 startTime = wallet.startTime();
        
        // Move to exactly when cliff ends
        vm.warp(startTime + CLIFF);
        assertEq(wallet.releasable(), 0); // Should be 0 at cliff end
        
        // Move 1 month after cliff (1/24 of vesting period)
        uint256 oneMonth = 30 days;
        vm.warp(startTime + CLIFF + oneMonth);
        uint256 expected = (TOTAL * oneMonth) / VESTING;
        assertEq(wallet.releasable(), expected);
    }
    
    function test_LinearVesting() public {
        uint256 startTime = wallet.startTime();
        
        // Test at various points during vesting
        uint256[] memory months = new uint256[](6);
        months[0] = 1;  // 1 month after cliff
        months[1] = 6;  // 6 months after cliff
        months[2] = 12; // 12 months after cliff (50% through vesting)
        months[3] = 18; // 18 months after cliff
        months[4] = 24; // 24 months after cliff (end of vesting)
        months[5] = 30; // 6 months after vesting ends
        
        for (uint256 i = 0; i < months.length; i++) {
            uint256 timeAfterCliff = months[i] * 30 days;
            vm.warp(startTime + CLIFF + timeAfterCliff);
            
            uint256 expectedVested;
            if (timeAfterCliff >= VESTING) {
                expectedVested = TOTAL; // Fully vested
            } else {
                expectedVested = (TOTAL * timeAfterCliff) / VESTING;
            }
            
            assertEq(wallet.releasable(), expectedVested);
        }
    }
    
    function test_Release() public {
        uint256 startTime = wallet.startTime();
        
        // Move to 6 months after cliff
        vm.warp(startTime + CLIFF + 180 days);
        
        uint256 expectedReleasable = (TOTAL * 180 days) / VESTING;
        assertEq(wallet.releasable(), expectedReleasable);
        
        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiary);
        
        // Release tokens
        wallet.release();
        
        // Check balances
        assertEq(token.balanceOf(beneficiary), beneficiaryBalanceBefore + expectedReleasable);
        assertEq(wallet.released(), expectedReleasable);
        assertEq(wallet.releasable(), 0); // Should be 0 after release
    }
    
    function test_MultipleReleases() public {
        uint256 startTime = wallet.startTime();
        
        // First release at 3 months after cliff
        vm.warp(startTime + CLIFF + 90 days);
        wallet.release();
        
        // Second release at 6 months after cliff
        vm.warp(startTime + CLIFF + 180 days);
        wallet.release();
        
        // Check total released
        uint256 expectedTotal = (TOTAL * 180 days) / VESTING;
        assertEq(wallet.released(), expectedTotal);
        assertEq(token.balanceOf(beneficiary), expectedTotal);
    }
    
    function test_FullVestingCycle() public {
        uint256 startTime = wallet.startTime();
        
        // Move to end of vesting period
        vm.warp(startTime + CLIFF + VESTING);
        
        assertEq(wallet.releasable(), TOTAL);
        
        // Release all tokens
        wallet.release();
        
        assertEq(token.balanceOf(beneficiary), TOTAL);
        assertEq(wallet.released(), TOTAL);
        assertEq(wallet.releasable(), 0);
        assertEq(token.balanceOf(address(wallet)), 0);
    }
    
    function test_ReleaseAfterFullVesting() public {
        uint256 startTime = wallet.startTime();
        
        // Move well past vesting period
        vm.warp(startTime + CLIFF + VESTING + 365 days);
        
        // Should still only be able to release total amount
        assertEq(wallet.releasable(), TOTAL);
        
        wallet.release();
        
        assertEq(token.balanceOf(beneficiary), TOTAL);
        assertEq(wallet.released(), TOTAL);
        
        // Try to release again - should fail
        vm.expectRevert("Nothing to release");
        wallet.release();
    }
    
    function test_CliffTiming() public {
        uint256 startTime = wallet.startTime();
        
        // Test exact cliff timing
        vm.warp(startTime + CLIFF - 1); // 1 second before cliff
        assertEq(wallet.releasable(), 0);
        
        vm.warp(startTime + CLIFF); // Exactly at cliff
        assertEq(wallet.releasable(), 0);
        
        vm.warp(startTime + CLIFF + 1); // 1 second after cliff
        uint256 expected = (TOTAL * 1) / VESTING;
        assertEq(wallet.releasable(), expected);
    }
    
    function test_VestingMath() public {
        uint256 startTime = wallet.startTime();
        
        // Test specific percentages - using arrays instead of struct
        uint256[5] memory daysAfterCliff = [uint256(365), 182, 730, 91, 548];
        uint256[5] memory expectedPercentages = [uint256(5000), 2493, 10000, 1247, 7507]; // in basis points
        
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(startTime + CLIFF + daysAfterCliff[i] * 1 days);
            uint256 releasable = wallet.releasable();
            uint256 actualPercentage = (releasable * 10000) / TOTAL;
            
            // Allow small rounding errors
            assertApproxEqAbs(actualPercentage, expectedPercentages[i], 1);
        }
    }
}