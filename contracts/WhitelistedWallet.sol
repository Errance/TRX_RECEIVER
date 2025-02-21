// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITRC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

contract WhitelistedWallet {
    // Contract owner address
    address public owner;
    
    // Whitelist mapping
    mapping(address => bool) public whitelist;
    
    // Supported tokens mapping (token address => is supported)
    mapping(address => bool) public supportedTokens;
    
    // Accumulated fees for each token
    mapping(address => uint256) public accumulatedFees;
    
    // USDC and USDT contract addresses (Shasta testnet)
    address private constant USDC = address(0x41A614F803B6FD780986A42C78EC9C7F77E6DED13C);
    address private constant USDT = address(0x41A614F803B6FD780986A42C78EC9C7F77E6DED13C);
    
    // Events
    event Received(address indexed token, address indexed sender, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount, uint256 fee);
    event WhitelistUpdated(address indexed account, bool status);
    event FeesWithdrawn(address indexed token, address indexed owner, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // Constructor
    constructor() {
        owner = msg.sender;
        whitelist[msg.sender] = true; // Add deployer to whitelist
        
        // Initialize supported tokens
        supportedTokens[address(0)] = true; // Support TRX
        supportedTokens[USDC] = true;       // Support USDC
        supportedTokens[USDT] = true;       // Support USDT
    }
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Address not whitelisted");
        _;
    }
    
    modifier onlySupportedToken(address token) {
        require(supportedTokens[token], "Token not supported");
        _;
    }
    
    // Receive TRX
    receive() external payable {
        emit Received(address(0), msg.sender, msg.value);
    }
    
    // Whitelist management
    function addToWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
        emit WhitelistUpdated(_address, true);
    }
    
    function removeFromWhitelist(address _address) external onlyOwner {
        require(_address != owner, "Cannot remove owner from whitelist");
        whitelist[_address] = false;
        emit WhitelistUpdated(_address, false);
    }
    
    function isWhitelisted(address _address) external view returns (bool) {
        return whitelist[_address];
    }
    
    // Token management
    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }
    
    // Deposit TRC20 tokens
    function depositTRC20(address token, uint256 amount) external onlySupportedToken(token) {
        require(ITRC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit Received(token, msg.sender, amount);
    }
    
    // Withdraw TRC20 tokens
    function withdrawTRC20(address token, uint256 amount) external onlyWhitelisted onlySupportedToken(token) {
        require(token != address(0), "Use withdrawTRX for TRX");
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 contractBalance = ITRC20(token).balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient contract balance");
        
        // Calculate 9% fee
        uint256 fee = (amount * 9) / 100;
        uint256 amountAfterFee = amount - fee;
        
        // Update accumulated fees
        accumulatedFees[token] += fee;
        
        // Transfer tokens (amount after fee)
        require(ITRC20(token).transfer(msg.sender, amountAfterFee), "Transfer failed");
        
        emit Withdrawn(token, msg.sender, amountAfterFee, fee);
    }
    
    // Withdraw TRX
    function withdrawTRX(uint256 amount) external onlyWhitelisted {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        // Calculate 9% fee
        uint256 fee = (amount * 9) / 100;
        uint256 amountAfterFee = amount - fee;
        
        // Update accumulated fees
        accumulatedFees[address(0)] += fee;
        
        // Transfer TRX (amount after fee)
        payable(msg.sender).transfer(amountAfterFee);
        
        emit Withdrawn(address(0), msg.sender, amountAfterFee, fee);
    }
    
    // Withdraw accumulated fees for specific token
    function withdrawFees(address token) external onlyOwner onlySupportedToken(token) {
        uint256 feesToWithdraw = accumulatedFees[token];
        require(feesToWithdraw > 0, "No fees to withdraw");
        
        accumulatedFees[token] = 0;
        
        if (token == address(0)) {
            // Withdraw TRX fees
            payable(owner).transfer(feesToWithdraw);
        } else {
            // Withdraw TRC20 token fees
            require(ITRC20(token).transfer(owner, feesToWithdraw), "Transfer failed");
        }
        
        emit FeesWithdrawn(token, owner, feesToWithdraw);
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        require(newOwner != owner, "New owner is current owner");
        
        address oldOwner = owner;
        owner = newOwner;
        whitelist[newOwner] = true; // Add new owner to whitelist
        
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    // Get contract balance for specific token
    function getTokenBalance(address token) external view onlySupportedToken(token) returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return ITRC20(token).balanceOf(address(this));
    }
}