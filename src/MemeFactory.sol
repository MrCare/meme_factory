// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Meme} from "./Meme.sol";
import {MinimalProxy} from "./MinimalProxy.sol";
import {TWAPOracle} from "./TWAPOracle.sol";
import {IUniswapV2Router02, IUniswapV2Factory} from "./interfaces/IUniswapV2.sol";

contract MemeFactory {
    address public implementation;
    MinimalProxy public proxy;
    address public owner;
    
    uint256 public constant PLATFORM_FEE_RATE = 500; // 5% = 500 / 10000
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Sepolia Uniswap V2 addresses
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
    IUniswapV2Factory public constant factory = IUniswapV2Factory(0x7E0987E5b3a30e3f2828572Bb659A548460a3003);
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    
    TWAPOracle public twapOracle;
    
    struct MemeInfo {
        string symbol;
        uint256 maxSupply;
        uint256 perMint;
        uint256 price;
        uint256 minted;
        address creator;
        bool exists;
        bool liquidityAdded;
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
    event LiquidityAdded(
        address indexed token,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 liquidity,
        address indexed creator
    );
    event MemeBought(
        address indexed token,
        address indexed buyer,
        uint256 amountIn,
        uint256 amountOut,
        string source // "mint" or "uniswap"
    );
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        implementation = address(new Meme());
        proxy = new MinimalProxy(implementation);
        twapOracle = new TWAPOracle(address(factory), WETH);
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
            exists: true,
            liquidityAdded: false
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
        uint256 platformFee = (totalCost * PLATFORM_FEE_RATE) / FEE_DENOMINATOR; // 5%
        uint256 creatorFee = totalCost - platformFee; // 95%
        
        // Mint tokens to user
        bool success = Meme(tokenAddr).mint(msg.sender);
        require(success, "Mint failed");
        
        // Get the actual perMint amount from the Meme contract (in wei)
        uint256 actualPerMint = Meme(tokenAddr).perMint();
        
        // Update minted amount
        memeInfo.minted += memeInfo.perMint;
        
        // Add liquidity with platform fee
        if (platformFee > 0) {
            _addLiquidity(tokenAddr, platformFee);
        }
        
        // Transfer creator fee
        if (creatorFee > 0) {
            payable(memeInfo.creator).transfer(creatorFee);
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        // Update TWAP oracle
        twapOracle.update(tokenAddr);
        
        emit MemeMinted(tokenAddr, msg.sender, actualPerMint, totalCost, platformFee, creatorFee);
        
        return true;
    }
    
    function _addLiquidity(address tokenAddr, uint256 ethAmount) internal {
        MemeInfo storage memeInfo = memes[tokenAddr];
        
        // Calculate token amount needed for liquidity at mint price
        uint256 tokenAmountForLiquidity = (ethAmount * 10**18) / memeInfo.price;
        
        // Mint tokens for liquidity to this contract
        bool mintSuccess = Meme(tokenAddr).mintForLiquidity(address(this), tokenAmountForLiquidity);
        require(mintSuccess, "Mint for liquidity failed");
        
        // Approve router to spend tokens
        Meme(tokenAddr).approve(address(router), tokenAmountForLiquidity);
        
        // Add liquidity - LP tokens go to creator (0% slippage)
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            tokenAddr,
            tokenAmountForLiquidity,    // amountTokenDesired
            tokenAmountForLiquidity,    // amountTokenMin (0% slippage)
            ethAmount,                  // amountETHMin (0% slippage)
            memeInfo.creator,           // LP tokens go to creator
            block.timestamp + 300       // deadline: 5 minutes
        );
        
        // Mark liquidity as added
        memeInfo.liquidityAdded = true;
        
        emit LiquidityAdded(tokenAddr, amountToken, amountETH, liquidity, memeInfo.creator);
    }
    
    function buyMeme(address tokenAddr) external payable returns (bool) {
        require(memes[tokenAddr].exists, "Meme not exists");
        require(msg.value > 0, "Invalid payment amount");
        
        MemeInfo memory memeInfo = memes[tokenAddr];
        
        // Get the best price and source
        (, bool useMint) = _getBestPrice(tokenAddr, msg.value);
        
        if (useMint) {
            // Use mint if it's better and available
            require(memeInfo.minted < memeInfo.maxSupply, "Mint sold out");
            
            uint256 mintCost = memeInfo.price * memeInfo.perMint;
            require(msg.value >= mintCost, "Insufficient payment for mint");
            
            // Call internal mint logic
            return _executeMint(tokenAddr, mintCost);
        } else {
            // Use Uniswap
            return _executeSwap(tokenAddr, msg.value);
        }
    }
    
    function _getBestPrice(address tokenAddr, uint256 ethAmount) internal view returns (uint256 price, bool useMint) {
        MemeInfo memory memeInfo = memes[tokenAddr];
        
        // If no liquidity added yet, can only mint
        if (!memeInfo.liquidityAdded) {
            return (memeInfo.price, true);
        }
        
        // If mint sold out, can only use Uniswap
        if (memeInfo.minted >= memeInfo.maxSupply) {
            uint256 uniswapPrice = _getUniswapPrice(tokenAddr, ethAmount);
            return (uniswapPrice, false);
        }
        
        // Compare prices
        uint256 mintTokens = (ethAmount * 10**18) / memeInfo.price;
        uint256 uniswapTokens = _getUniswapPrice(tokenAddr, ethAmount);
        
        // Use mint if it gives more tokens
        if (mintTokens > uniswapTokens) {
            return (memeInfo.price, true);
        } else {
            return (uniswapTokens, false);
        }
    }
    
    function _getUniswapPrice(address tokenAddr, uint256 ethAmount) internal view returns (uint256) {
        try twapOracle.getTWAPPrice(tokenAddr, ethAmount) returns (uint256 twapPrice) {
            return twapPrice;
        } catch {
            // Fallback to instant price if TWAP not available
            return twapOracle.getInstantPrice(tokenAddr, ethAmount);
        }
    }
    
    function _executeMint(address tokenAddr, uint256 mintCost) internal returns (bool) {
        MemeInfo storage memeInfo = memes[tokenAddr];
        
        // Calculate fees
        uint256 platformFee = (mintCost * PLATFORM_FEE_RATE) / FEE_DENOMINATOR;
        uint256 creatorFee = mintCost - platformFee;
        
        // Mint tokens to user
        bool success = Meme(tokenAddr).mint(msg.sender);
        require(success, "Mint failed");
        
        uint256 actualPerMint = Meme(tokenAddr).perMint();
        memeInfo.minted += memeInfo.perMint;
        
        // Add liquidity with platform fee
        if (platformFee > 0) {
            _addLiquidity(tokenAddr, platformFee);
        }
        
        // Transfer creator fee
        if (creatorFee > 0) {
            payable(memeInfo.creator).transfer(creatorFee);
        }
        
        // Refund excess payment
        if (msg.value > mintCost) {
            payable(msg.sender).transfer(msg.value - mintCost);
        }
        
        // Update TWAP oracle
        twapOracle.update(tokenAddr);
        
        emit MemeBought(tokenAddr, msg.sender, msg.value, actualPerMint, "mint");
        
        return true;
    }
    
    function _executeSwap(address tokenAddr, uint256 ethAmount) internal returns (bool) {
        // Prepare path for swap
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenAddr;
        
        // Get expected output with 0% slippage
        uint256 expectedOut = _getUniswapPrice(tokenAddr, ethAmount);
        
        // Execute swap
        uint256[] memory amounts = router.swapExactETHForTokens{value: ethAmount}(
            expectedOut,        // amountOutMin (0% slippage tolerance)
            path,
            msg.sender,
            block.timestamp + 300
        );
        
        // Update TWAP oracle
        twapOracle.update(tokenAddr);
        
        emit MemeBought(tokenAddr, msg.sender, ethAmount, amounts[1], "uniswap");
        
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
    
    function getPriceInfo(address tokenAddr, uint256 ethAmount) external view returns (
        uint256 mintPrice,
        uint256 uniswapPrice,
        bool shouldUseMint,
        bool canMint
    ) {
        require(memes[tokenAddr].exists, "Meme not exists");
        
        MemeInfo memory memeInfo = memes[tokenAddr];
        mintPrice = memeInfo.price;
        canMint = memeInfo.minted < memeInfo.maxSupply;
        
        if (memeInfo.liquidityAdded) {
            uniswapPrice = _getUniswapPrice(tokenAddr, ethAmount);
            
            if (canMint) {
                uint256 mintTokens = (ethAmount * 10**18) / mintPrice;
                uint256 uniswapTokens = uniswapPrice;
                shouldUseMint = mintTokens > uniswapTokens;
            } else {
                shouldUseMint = false;
            }
        } else {
            uniswapPrice = 0;
            shouldUseMint = canMint;
        }
    }
    
    function updateTWAP(address tokenAddr) external {
        require(memes[tokenAddr].exists, "Meme not exists");
        twapOracle.update(tokenAddr);
    }
    
    function canUpdateTWAP(address tokenAddr) external view returns (bool) {
        return twapOracle.canUpdateTWAP(tokenAddr);
    }
}
