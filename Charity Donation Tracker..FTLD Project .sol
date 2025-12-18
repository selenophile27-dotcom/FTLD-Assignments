// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// =========== MODULE 3: ABSTRACT CONTRACT ===========
abstract contract CharityBase {
    address public owner;
    uint256 public totalDonations;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Abstract function (Module 3)
    function donate() public payable virtual;
}

// =========== MODULE 5: ORACLE SIMULATION ===========
contract MockOracle {
    // Simple mock oracle for demonstration (Module 5)
    mapping(string => uint256) public exchangeRates;
    
    constructor() {
        // Initialize with some mock rates
        exchangeRates["ETH/USD"] = 2000 * 10**8; // $2000
        exchangeRates["DAI/ETH"] = 1 * 10**18; // 1:1
    }
    
    function getRate(string memory pair) external view returns (uint256) {
        return exchangeRates[pair];
    }
    
    function setRate(string memory pair, uint256 rate) external {
        exchangeRates[pair] = rate;
    }
}

// =========== MAIN CHARITY CONTRACT ===========
contract CharityDonationTracker is CharityBase {
    // =========== MODULE 2: STRUCTS & ARRAYS ===========
    struct Donor {
        address wallet;
        uint256 totalDonated;
        uint256 lastDonation;
        uint256 donationCount;
    }
    
    struct Milestone {
        uint256 id;
        string description;
        uint256 targetAmount;
        uint256 releasedAmount;
        bool completed;
        uint256 completionTime;
    }
    
    Donor[] public donors;
    mapping(address => uint256) public donorIndex;
    Milestone[] public milestones;
    
    MockOracle public oracle;
    string public currencyPair = "ETH/USD";
    
    event DonationReceived(address donor, uint256 amount, uint256 usdValue);
    event MilestoneAdded(uint256 milestoneId, string description, uint256 target);
    event MilestoneCompleted(uint256 milestoneId, uint256 released);
    event FundsWithdrawn(address recipient, uint256 amount);
    
    constructor(address _oracleAddress) CharityBase() {
        oracle = MockOracle(_oracleAddress);
    }
    
    // =========== MODULE 1: BASIC FUNCTIONS ===========
    function donate() public payable override {
        require(msg.value > 0, "Donation must be > 0");
        
        // Update donor info
        if (donorIndex[msg.sender] == 0 && msg.sender != owner) {
            donors.push(Donor({
                wallet: msg.sender,
                totalDonated: msg.value,
                lastDonation: block.timestamp,
                donationCount: 1
            }));
            donorIndex[msg.sender] = donors.length;
        } else if (msg.sender != owner) {
            uint256 index = donorIndex[msg.sender] - 1;
            donors[index].totalDonated += msg.value;
            donors[index].lastDonation = block.timestamp;
            donors[index].donationCount += 1;
        }
        
        totalDonations += msg.value;
        
        // Module 5: Oracle integration
        uint256 usdValue = getDonationValueInUSD(msg.value);
        emit DonationReceived(msg.sender, msg.value, usdValue);
        
        // Check milestones
        checkMilestones();
    }
    
    // =========== MODULE 4: LOW-LEVEL CALLS ===========
    function getDonationValueInUSD(uint256 ethAmount) public view returns (uint256) {
        // Using oracle data (Module 5)
        uint256 rate = oracle.getRate(currencyPair);
        return (ethAmount * rate) / 10**18;
    }
    
    // =========== MODULE 3: MODIFIERS & ACCESS CONTROL ===========
    function addMilestone(string memory _description, uint256 _targetAmount) external onlyOwner {
        require(_targetAmount > 0, "Target must be > 0");
        
        uint256 milestoneId = milestones.length;
        milestones.push(Milestone({
            id: milestoneId,
            description: _description,
            targetAmount: _targetAmount,
            releasedAmount: 0,
            completed: false,
            completionTime: 0
        }));
        
        emit MilestoneAdded(milestoneId, _description, _targetAmount);
    }
    
    // =========== MODULE 2: LOOPS & CONTROL FLOW ===========
    function checkMilestones() internal {
        for (uint256 i = 0; i < milestones.length; i++) {
            if (!milestones[i].completed && totalDonations >= milestones[i].targetAmount) {
                milestones[i].completed = true;
                milestones[i].completionTime = block.timestamp;
                emit MilestoneCompleted(i, milestones[i].targetAmount);
            }
        }
    }
    
    // =========== MODULE 7: SECURITY PATTERNS ===========
    function withdrawFunds(uint256 amount, address payable recipient) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        
        // Checks-effects-interactions pattern (Module 7)
        uint256 currentBalance = address(this).balance;
        
        // Check milestones completed
        bool allMilestonesCompleted = true;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (!milestones[i].completed) {
                allMilestonesCompleted = false;
                break;
            }
        }
        
        if (!allMilestonesCompleted) {
            require(amount <= currentBalance / 2, "Can only withdraw 50% before all milestones");
        }
        
        // Interaction
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit FundsWithdrawn(recipient, amount);
    }
    
    // =========== MODULE 6: DEBUGGING & VIEW FUNCTIONS ===========
    function getDonorStats(address donor) external view returns (
        uint256 totalDonated,
        uint256 donationCount,
        uint256 lastDonation,
        uint256 usdValue
    ) {
        if (donorIndex[donor] == 0) {
            return (0, 0, 0, 0);
        }
        
        uint256 index = donorIndex[donor] - 1;
        Donor memory d = donors[index];
        uint256 usdVal = getDonationValueInUSD(d.totalDonated);
        
        return (d.totalDonated, d.donationCount, d.lastDonation, usdVal);
    }
    
    function getTopDonors(uint256 count) external view returns (address[] memory, uint256[] memory) {
        uint256 actualCount = count < donors.length ? count : donors.length;
        
        address[] memory topAddresses = new address[](actualCount);
        uint256[] memory topAmounts = new uint256[](actualCount);
        
        if (actualCount == 0) {
            return (topAddresses, topAmounts);
        }
        
        // Build an indices array in memory and sort indices to avoid modifying storage
        uint256 donorLen = donors.length;
        uint256[] memory indices = new uint256[](donorLen);
        for (uint256 i = 0; i < donorLen; i++) {
            indices[i] = i;
        }
        
        // Simple selection sort on indices based on donors[indices[*]].totalDonated
        for (uint256 i = 0; i < actualCount; i++) {
            uint256 maxPos = i;
            for (uint256 j = i + 1; j < donorLen; j++) {
                if (donors[indices[j]].totalDonated > donors[indices[maxPos]].totalDonated) {
                    maxPos = j;
                }
            }
            // swap indices
            if (maxPos != i) {
                uint256 tmp = indices[i];
                indices[i] = indices[maxPos];
                indices[maxPos] = tmp;
            }
            
            topAddresses[i] = donors[indices[i]].wallet;
            topAmounts[i] = donors[indices[i]].totalDonated;
        }
        
        return (topAddresses, topAmounts);
    }
    
    function getMilestoneStatus() external view returns (
        uint256 completed,
        uint256 pending,
        uint256 totalRaised,
        uint256 nextTarget
    ) {
        uint256 comp = 0;
        uint256 pend = 0;
        
        for (uint256 i = 0; i < milestones.length; i++) {
            if (milestones[i].completed) {
                comp++;
            } else {
                pend++;
            }
        }
        
        uint256 next = 0;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (!milestones[i].completed) {
                next = milestones[i].targetAmount;
                break;
            }
        }
        
        return (comp, pend, totalDonations, next);
    }
    
    // =========== MODULE 4: RECEIVE & FALLBACK ===========
    receive() external payable {
        donate();
    }
    
    fallback() external {
        revert("Invalid function call");
    }
}