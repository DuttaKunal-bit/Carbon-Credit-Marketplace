// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title EcoTrade - Carbon Credit Marketplace
 * @dev Decentralized marketplace for trading verified carbon credits
 * @author EcoTrade Team
 */

// ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract CarbonCreditMarketplace is ReentrancyGuard, Ownable {
    
    // Carbon Credit structure
    struct CarbonCredit {
        uint256 id;
        address owner;
        string projectName;
        string projectType; // e.g., "Reforestation", "Solar Energy", "Wind Power"
        string location;
        uint256 carbonOffset; // CO2 tons offset
        uint256 pricePerTon; // Price in wei per ton
        bool isAvailable;
        bool isVerified;
        uint256 creationDate;
        string certificationBody; // e.g., "VCS", "Gold Standard", "CDM"
    }
    
    // Market Order structure
    struct MarketOrder {
        uint256 orderId;
        uint256 creditId;
        address seller;
        uint256 quantity; // Tons to sell
        uint256 pricePerTon;
        bool isActive;
        uint256 orderDate;
    }
    
    // State variables
    mapping(uint256 => CarbonCredit) public carbonCredits;
    mapping(uint256 => MarketOrder) public marketOrders;
    mapping(address => uint256[]) public userCredits;
    mapping(address => bool) public verifiedIssuers;
    mapping(address => uint256) public userCarbonBalance; // Total carbon offset owned
    
    uint256 public nextCreditId = 1;
    uint256 public nextOrderId = 1;
    uint256 public platformFee = 200; // 2% in basis points
    uint256 public totalCarbonTraded;
    uint256 public totalCreditsIssued;
    
    // Events
    event CreditMinted(
        uint256 indexed creditId,
        address indexed issuer,
        string projectName,
        uint256 carbonOffset,
        uint256 pricePerTon
    );
    
    event CreditListed(
        uint256 indexed orderId,
        uint256 indexed creditId,
        address indexed seller,
        uint256 quantity,
        uint256 pricePerTon
    );
    
    event CreditPurchased(
        uint256 indexed orderId,
        address indexed buyer,
        address indexed seller,
        uint256 quantity,
        uint256 totalAmount
    );
    
    event CreditRetired(
        uint256 indexed creditId,
        address indexed owner,
        uint256 quantity,
        string reason
    );
    
    event IssuerVerified(address indexed issuer);
    
    // Modifiers
    modifier onlyVerifiedIssuer() {
        require(verifiedIssuers[msg.sender], "Not a verified issuer");
        _;
    }
    
    modifier validCreditId(uint256 _creditId) {
        require(_creditId > 0 && _creditId < nextCreditId, "Invalid credit ID");
        require(carbonCredits[_creditId].id != 0, "Credit does not exist");
        _;
    }
    
    modifier onlyCreditOwner(uint256 _creditId) {
        require(carbonCredits[_creditId].owner == msg.sender, "Not credit owner");
        _;
    }
    
    constructor() {
        verifiedIssuers[msg.sender] = true; // Contract deployer is verified
    }
    
    /**
     * @dev Function 1: Mint new carbon credits
     * @param _projectName Name of the carbon offset project
     * @param _projectType Type of project (Reforestation, Solar, etc.)
     * @param _location Geographic location of the project
     * @param _carbonOffset Amount of CO2 offset in tons
     * @param _pricePerTon Initial price per ton in wei
     * @param _certificationBody Certification authority
     */
    function mintCarbonCredit(
        string memory _projectName,
        string memory _projectType,
        string memory _location,
        uint256 _carbonOffset,
        uint256 _pricePerTon,
        string memory _certificationBody
    ) external onlyVerifiedIssuer returns (uint256) {
        require(_carbonOffset > 0, "Carbon offset must be positive");
        require(_pricePerTon > 0, "Price must be positive");
        require(bytes(_projectName).length > 0, "Project name required");
        
        uint256 creditId = nextCreditId++;
        
        carbonCredits[creditId] = CarbonCredit({
            id: creditId,
            owner: msg.sender,
            projectName: _projectName,
            projectType: _projectType,
            location: _location,
            carbonOffset: _carbonOffset,
            pricePerTon: _pricePerTon,
            isAvailable: true,
            isVerified: true,
            creationDate: block.timestamp,
            certificationBody: _certificationBody
        });
        
        userCredits[msg.sender].push(creditId);
        userCarbonBalance[msg.sender] += _carbonOffset;
        totalCreditsIssued++;
        
        emit CreditMinted(creditId, msg.sender, _projectName, _carbonOffset, _pricePerTon);
        return creditId;
    }
    
    /**
     * @dev Function 2: List carbon credit for sale
     * @param _creditId ID of the carbon credit to sell
     * @param _quantity Amount of carbon tons to sell
     * @param _pricePerTon Selling price per ton in wei
     */
    function listCreditForSale(
        uint256 _creditId,
        uint256 _quantity,
        uint256 _pricePerTon
    ) external validCreditId(_creditId) onlyCreditOwner(_creditId) returns (uint256) {
        CarbonCredit storage credit = carbonCredits[_creditId];
        require(credit.isAvailable, "Credit not available");
        require(_quantity > 0 && _quantity <= credit.carbonOffset, "Invalid quantity");
        require(_pricePerTon > 0, "Price must be positive");
        
        uint256 orderId = nextOrderId++;
        
        marketOrders[orderId] = MarketOrder({
            orderId: orderId,
            creditId: _creditId,
            seller: msg.sender,
            quantity: _quantity,
            pricePerTon: _pricePerTon,
            isActive: true,
            orderDate: block.timestamp
        });
        
        // Update credit price if listing full amount
        if (_quantity == credit.carbonOffset) {
            credit.pricePerTon = _pricePerTon;
        }
        
        emit CreditListed(orderId, _creditId, msg.sender, _quantity, _pricePerTon);
        return orderId;
    }
    
    /**
     * @dev Function 3: Purchase carbon credits from marketplace
     * @param _orderId ID of the market order to purchase
     * @param _quantity Amount of carbon tons to purchase
     */
    function purchaseCarbonCredit(
        uint256 _orderId,
        uint256 _quantity
    ) external payable nonReentrant {
        require(_orderId > 0 && _orderId < nextOrderId, "Invalid order ID");
        
        MarketOrder storage order = marketOrders[_orderId];
        require(order.isActive, "Order not active");
        require(_quantity > 0 && _quantity <= order.quantity, "Invalid quantity");
        require(msg.sender != order.seller, "Cannot buy own credit");
        
        uint256 totalCost = _quantity * order.pricePerTon;
        require(msg.value >= totalCost, "Insufficient payment");
        
        // Calculate platform fee
        uint256 fee = (totalCost * platformFee) / 10000;
        uint256 sellerAmount = totalCost - fee;
        
        // Create new credit for buyer or transfer ownership
        _transferCreditOwnership(order.creditId, msg.sender, _quantity);
        
        // Update order
        order.quantity -= _quantity;
        if (order.quantity == 0) {
            order.isActive = false;
        }
        
        // Update balances
        userCarbonBalance[msg.sender] += _quantity;
        userCarbonBalance[order.seller] -= _quantity;
        totalCarbonTraded += _quantity;
        
        // Transfer payments
        (bool successSeller, ) = payable(order.seller).call{value: sellerAmount}("");
        require(successSeller, "Transfer to seller failed");
        
        (bool successOwner, ) = payable(owner()).call{value: fee}("");
        require(successOwner, "Transfer to owner failed");
        
        // Refund excess
        if (msg.value > totalCost) {
            (bool successRefund, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(successRefund, "Refund failed");
        }
        
        emit CreditPurchased(_orderId, msg.sender, order.seller, _quantity, totalCost);
    }
    
    /**
     * @dev Function 4: Retire carbon credits (remove from circulation)
     * @param _creditId ID of the carbon credit to retire
     * @param _quantity Amount of carbon tons to retire
     * @param _reason Reason for retirement (offsetting, CSR, etc.)
     */
    function retireCarbonCredit(
        uint256 _creditId,
        uint256 _quantity,
        string memory _reason
    ) external validCreditId(_creditId) onlyCreditOwner(_creditId) {
        CarbonCredit storage credit = carbonCredits[_creditId];
        require(credit.isAvailable, "Credit not available");
        require(_quantity > 0 && _quantity <= credit.carbonOffset, "Invalid quantity");
        
        // Reduce credit amount or mark as unavailable
        credit.carbonOffset -= _quantity;
        if (credit.carbonOffset == 0) {
            credit.isAvailable = false;
        }
        
        // Update user balance
        userCarbonBalance[msg.sender] -= _quantity;
        
        emit CreditRetired(_creditId, msg.sender, _quantity, _reason);
    }
    
    /**
     * @dev Function 5: Verify new carbon credit issuers
     * @param _issuer Address of the issuer to verify
     */
    function verifyIssuer(address _issuer) external onlyOwner {
        require(_issuer != address(0), "Invalid address");
        require(!verifiedIssuers[_issuer], "Already verified");
        
        verifiedIssuers[_issuer] = true;
        emit IssuerVerified(_issuer);
    }
    
    /**
     * @dev Internal function to handle credit ownership transfer
     */
    function _transferCreditOwnership(
        uint256 _creditId,
        address _newOwner,
        uint256 _quantity
    ) internal returns (uint256) {
        CarbonCredit storage originalCredit = carbonCredits[_creditId];
        
        if (_quantity == originalCredit.carbonOffset) {
            // Transfer full ownership
            originalCredit.owner = _newOwner;
            userCredits[_newOwner].push(_creditId);
            return _creditId;
        } else {
            // Create new credit for partial transfer
            uint256 newCreditId = nextCreditId++;
            
            carbonCredits[newCreditId] = CarbonCredit({
                id: newCreditId,
                owner: _newOwner,
                projectName: originalCredit.projectName,
                projectType: originalCredit.projectType,
                location: originalCredit.location,
                carbonOffset: _quantity,
                pricePerTon: originalCredit.pricePerTon,
                isAvailable: true,
                isVerified: true,
                creationDate: originalCredit.creationDate,
                certificationBody: originalCredit.certificationBody
            });
            
            // Reduce original credit amount
            originalCredit.carbonOffset -= _quantity;
            
            userCredits[_newOwner].push(newCreditId);
            return newCreditId;
        }
    }
    
    // View functions
    function getCreditDetails(uint256 _creditId) 
        external 
        view 
        validCreditId(_creditId) 
        returns (CarbonCredit memory) 
    {
        return carbonCredits[_creditId];
    }
    
    function getOrderDetails(uint256 _orderId) 
        external 
        view 
        returns (MarketOrder memory) 
    {
        require(_orderId > 0 && _orderId < nextOrderId, "Invalid order ID");
        return marketOrders[_orderId];
    }
    
    function getUserCredits(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userCredits[_user];
    }
    
    function getMarketStats() 
        external 
        view 
        returns (uint256, uint256, uint256) 
    {
        return (totalCreditsIssued, totalCarbonTraded, nextCreditId - 1);
    }
    
    // Admin functions
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 500, "Fee too high"); // Max 5%
        platformFee = _newFee;
    }
    
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
}
