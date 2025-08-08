// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

contract Meme is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    uint256 public maxSupply;
    uint256 public perMint;
    uint256 public minted;
    uint256 public price;
    address public factory;
    address public creator;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    bool private initialized;
    
    function initialize(
        string memory _symbol, 
        uint256 _maxSupply, 
        uint256 _perMint,
        uint256 _price,
        address _creator,
        address _factory
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;
        decimals = 18;  // 显式设置decimals
        name = string(abi.encodePacked("Meme ", _symbol));
        symbol = _symbol;
        maxSupply = _maxSupply * 10**decimals;
        perMint = _perMint * 10**decimals;
        price = _price;
        creator = _creator;
        factory = _factory;
    }
    
    function mint(address to) external returns (bool) {
        require(msg.sender == factory, "Only factory can mint");
        require(minted + perMint <= maxSupply, "Exceeds max supply");
        
        minted += perMint;
        totalSupply += perMint;
        balanceOf[to] += perMint;
        
        emit Transfer(address(0), to, perMint);
        return true;
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }
}
