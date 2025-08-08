// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";

contract CliffWallet {
    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public released;
    
    uint256 constant CLIFF = 365 days; // 12 months
    uint256 constant VESTING = 730 days; // 24 months
    uint256 constant TOTAL = 1_000_000e18; // 1M tokens
    
    constructor(address _beneficiary, address _token) {
        beneficiary = _beneficiary;
        token = IERC20(_token);
        startTime = block.timestamp;
        
        token.transferFrom(msg.sender, address(this), TOTAL);
    }
    
    function release() external {
        uint256 __releasable = _releasable();
        require(__releasable > 0, "Nothing to release");

        released += __releasable;
        token.transfer(beneficiary, __releasable);
    }
    
    function _releasable() internal view returns (uint256) {
        return _vested() - released;
    }
    
    function _vested() internal view returns (uint256) {
        if (block.timestamp < startTime + CLIFF) return 0;
        if (block.timestamp >= startTime + CLIFF + VESTING) return TOTAL;
        
        uint256 timeAfterCliff = block.timestamp - startTime - CLIFF;
        return (TOTAL * timeAfterCliff) / VESTING;
    }
    
    function releasable() external view returns (uint256) {
        return _releasable();
    }
}