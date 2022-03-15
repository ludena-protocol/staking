// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract YeildFarmingKingRival is ReentrancyGuard, AccessControl, Ownable, Pausable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    // stored current itemid
    Counters.Counter private _reward;
    // stored number of item sold
    Counters.Counter private _packageUserId;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGERMENT_ROLE = keccak256("MANAGERMENT_ROLE");

    address private lpTokenAddress; // address of LP token
    uint256 private lockTimePrize; // time lock prize
    uint256 private rewardPrizeIn1Second; // reward prize in 1 second
    uint256 startBlockReward; // time start block reward
    uint256 totalRewardPrizeClaim; // total token LP stake
    bool isEnable = true; // total token LP stake
    uint256 timeIsDisable = 0; // total token LP stake
    uint256 tokenPrizeInDisable = 0; // total token LP stake

    struct UserInfor {
        uint256 amountStake;
        uint256 timeStake;
    }

    struct UserPrizeLock {
        uint256 amount;
        uint256 timeUnlock;
        bool isClaim;
    }

    struct OverView {
        uint256 amount;
        uint256 timeUnlock;
    }


    event depositStakeEvent(address user, uint256 amountStake, uint256 timeStake);
    event withDrawStakeEvent(address user, uint256 amountStake, uint256 timeStake);
    event havestRewardEvent(address user, uint256 prizeId, uint256 prize, uint256 timeUnlock);
    event gatherRewardEvent(address user, uint256 prizeId, uint256 prizeClaim);
    event changeLockTimePrizeEvent(address user, uint256 _newLockTimePrize);
    event ChangeRewardPrizeIn1SecondEvent(address user, uint256 _newTokenPrize);
    
    mapping(address => UserInfor) private userInfor;
    mapping(address => mapping(uint256 => UserPrizeLock)) private userLockPrize;
    mapping(address => uint256) private countUserPrizeLock;
    mapping(address => uint256) private indexPriceNotClaim;
    mapping(address => uint256) private totalTokenLockUser;

    address tokenBaseAddress;
    constructor(address _tokenBase, address _lpTokenAddress, uint256 _lockTimePrize) {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MANAGERMENT_ROLE, MANAGERMENT_ROLE);
        _setupRole(ADMIN_ROLE, _msgSender());
        _setupRole(MANAGERMENT_ROLE, _msgSender());
        tokenBaseAddress = _tokenBase;
        lpTokenAddress = _lpTokenAddress;
        lockTimePrize = _lockTimePrize;
        startBlockReward = block.timestamp;
    }

    /**
     * change Lock time prize
     * @param _lockTimePrize: new locktime prize
     */
    function changeLockTimePrize(uint256 _lockTimePrize) external onlyRole(MANAGERMENT_ROLE) {
        lockTimePrize = _lockTimePrize;
        emit changeLockTimePrizeEvent(msg.sender, _lockTimePrize);
    }

    /**
     * change token prize in year
     * @param totalTokenInYear: total total in a year
     */
    function changeRewardPrizeIn1Second(uint256 totalTokenInYear) external onlyRole(MANAGERMENT_ROLE) {
        require(isEnable, "pool is closed");
        if (totalTokenInYear > 0){
            isEnable = true;
        } else {
            isEnable = false;
            timeIsDisable = block.timestamp;
            tokenPrizeInDisable = rewardPrizeIn1Second;
        }
        rewardPrizeIn1Second = totalTokenInYear.div(31536000); //31536000 = 86400 * 365 day 
        emit ChangeRewardPrizeIn1SecondEvent(msg.sender, totalTokenInYear);
    }
    

    function pause() public onlyRole(MANAGERMENT_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(MANAGERMENT_ROLE) {
        _unpause();
    }

    /**
     * deposit LP token in to farming
     * @param amountLPLiquidity: lp token stake
     */
    function DepositStake(uint256 amountLPLiquidity) external whenNotPaused {
        require(amountLPLiquidity > 0, "amount LP need bigger than zero");
        require(isEnable, "LP pool is close");
        IERC20(lpTokenAddress).transferFrom(msg.sender, address(this), amountLPLiquidity);
        uint256 amountStake = userInfor[msg.sender].amountStake;
        uint256 timeStake = userInfor[msg.sender].timeStake;
        uint256 timeNow = block.timestamp;
        if (amountStake > 0){
           _harvestReward(amountStake, timeStake, timeNow);
        } else {
            userInfor[msg.sender].timeStake = timeNow;
        }
        userInfor[msg.sender].amountStake = amountStake + amountLPLiquidity;
        emit depositStakeEvent(msg.sender, amountLPLiquidity, timeNow);
    }

    /**
     * withdrew LP token from farming
     * @param amountLPLiquidity: lp token stake
     */
    function WithdrawStake(uint256 amountLPLiquidity) external {
        require(amountLPLiquidity > 0, "amount LP need bigger than zero");
        uint256 amountStake = userInfor[msg.sender].amountStake;
        uint256 timeStake = userInfor[msg.sender].timeStake;
        uint256 timeNow;
        if(isEnable) {
            timeNow = block.timestamp;
        } else {
            timeNow = timeIsDisable;
        }
        _harvestReward(amountStake, timeStake, timeNow);

        require(amountStake > 0, "user don't have token LP in pool");
        require(amountStake >= amountLPLiquidity, "amount withdraw is must smaller amount stake");
        IERC20(lpTokenAddress).transfer(msg.sender, amountLPLiquidity);

        userInfor[msg.sender].amountStake = amountStake - amountLPLiquidity;
        userInfor[msg.sender].timeStake = timeNow;
        emit withDrawStakeEvent(msg.sender, amountLPLiquidity, timeNow);
    }

    /**
     * calcutate prize of user
     * @param amountStake: lp token stake
     * @param timeLock: time stake lock lp token
     */
    function _calculatePrize(uint256 amountStake, uint256 timeLock ) internal view returns (uint256) {
        uint256 balance = IERC20(lpTokenAddress).balanceOf(address(this));
        uint256 prize;
        if (isEnable){
            prize = amountStake.mul(rewardPrizeIn1Second).mul(timeLock).div(balance);
        } else {
            prize = amountStake.mul(tokenPrizeInDisable).mul(timeLock).div(balance); 
        }
        return prize;
    }

    /**
     * get prize reward with not change stake
     */
    function harvestReward() external {
        uint256 amountStake = userInfor[msg.sender].amountStake;
        require(amountStake > 0, "user don't have token LP in pool");
        uint256 timeStake = userInfor[msg.sender].timeStake;
        uint256 timeNow;
        if(isEnable) {
            timeNow = block.timestamp;
        } else {
            timeNow = timeIsDisable;
        }
        _harvestReward(amountStake, timeStake, timeNow);
        userInfor[msg.sender].timeStake = timeNow;
    }

    /**
     * calculate and lock prize
     * @param amountStake: lp token stake
     * @param timeStake: time when start stake
     * @param timeNow: timestamp now
     */
    function _harvestReward(uint256 amountStake, uint256 timeStake, uint256 timeNow) internal {
        uint256 timeLock = timeNow.sub(timeStake);
        uint256 prize = _calculatePrize(amountStake, timeLock);

        uint256 count = countUserPrizeLock[msg.sender];
        uint256 totalLockPrizeUser = totalTokenLockUser[msg.sender];

        UserPrizeLock memory userPrize;
        userPrize.amount = prize;
        userPrize.timeUnlock = timeNow.add(lockTimePrize);
        userPrize.isClaim = false;

        userLockPrize[msg.sender][count] = userPrize;
        countUserPrizeLock[msg.sender] = count + 1;
        userInfor[msg.sender].timeStake = block.timestamp;
        totalTokenLockUser[msg.sender] = totalLockPrizeUser.add(prize);
        emit havestRewardEvent(msg.sender, count, userPrize.amount, userPrize.timeUnlock);
    }

    /**
     * gather prize when token prize unlock
     */
    function gatherReward() external {
        uint256 indexClaim = indexPriceNotClaim[msg.sender];
        uint256 totalLockPrize = countUserPrizeLock[msg.sender];
        uint256 totalLockPrizeUser = totalTokenLockUser[msg.sender];
        uint256 timeNow = block.timestamp;
        uint256 indexClaimNew = indexClaim.add(1);
        uint256 totalRewardPrizeClaimOld = totalRewardPrizeClaim;

        require(indexClaim < totalLockPrize, "index claim is not bigger than total lock prize");
        require(!userLockPrize[msg.sender][indexClaim].isClaim, "prize is claimed");
        require(userLockPrize[msg.sender][indexClaim].timeUnlock < timeNow, "token is locked");

        uint256 prizeClaim = userLockPrize[msg.sender][indexClaim].amount;
        userLockPrize[msg.sender][indexClaim].isClaim = true;
        userLockPrize[msg.sender][indexClaim].amount = 0;

        require(prizeClaim > 0, "price claim must bigger thanh zero");
        indexPriceNotClaim[msg.sender] = indexClaimNew;
        IERC20(tokenBaseAddress).transfer(msg.sender, prizeClaim);
        totalRewardPrizeClaim = totalRewardPrizeClaimOld.add(prizeClaim);
        totalTokenLockUser[msg.sender] = totalLockPrizeUser.sub(prizeClaim);
        emit gatherRewardEvent(msg.sender, indexClaim, prizeClaim);
    }

    /**
     * get total token stake in pool farming
     */
    function getTotalStakeLP() external view returns(uint256) {
        return IERC20(lpTokenAddress).balanceOf(address(this));
    }

    /**
     * get total prize amount of coins paid
     */
    function getTotalTokenReward() public view returns(uint256) {
        uint256 time = block.timestamp; 
        uint256 timeStart = time.sub(startBlockReward); 
        uint256 totalTokenReward = timeStart.mul(rewardPrizeIn1Second);
        return totalTokenReward;
    }

    /**
     * get total prize amount of coins paid and unlock
     */
    function getTotalTokenRewardUnLock() public view returns(uint256) {
        uint256 time = block.timestamp; 
        uint256 timeStart = time.sub(startBlockReward); 
        uint256 totalPrize = timeStart.mul(rewardPrizeIn1Second);
        uint256 totalTokenUnLock = 0;
        uint256 totalTokenLock = lockTimePrize.mul(rewardPrizeIn1Second);
        if(totalTokenLock < totalPrize){
            totalTokenUnLock = totalPrize.sub(totalTokenLock).sub(totalRewardPrizeClaim);
        }
        return totalTokenUnLock;
    }

    /**
     * get index claim of user
     * @param user: user address
     */
    function getIndexClaimofUser(address user) external view returns(uint256) {
        return indexPriceNotClaim[user];
    }

    /**
     * get number prize package lock of user
     * @param user: user address
     */
    function getCountPrizeLockofUser(address user) external view returns(uint256) {
        return countUserPrizeLock[user];
    }

    /**
     * get prize amount lock of user
     * @param user: user address
     */
    function getAmountPrizeofUser(address user) external view returns(uint256) {
        uint256 indexClaim = indexPriceNotClaim[user];
        return userLockPrize[user][indexClaim].amount;
    }

    /**
     * get time when data is unlock
     * @param user: user address
     */
    function getTimeUnlockAmountPrizeofUser(address user) external view returns(uint256) {
        uint256 indexClaim = indexPriceNotClaim[user];
        return userLockPrize[user][indexClaim].timeUnlock;
    }

    /**
     * get total token prize unlock which can gather
     * @param user: user address
     */
    function getTotalPrizeofUser(address user) external view returns(uint256) {
        return totalTokenLockUser[user];
    }

    /**
     * get amount stake of user
     * @param user: user address
     */
    function getInforAmountStakeOfUser(address user) external view returns(uint256) {
        return  userInfor[user].amountStake;
    }

    /**
     * get time start stake of user
     * @param user: user address
     */
    function getInforTimeStakeStartOfUser(address user) external view returns(uint256) {
        return userInfor[user].timeStake;
    }

    /**
     * get prize can havest of user
     * @param user: user address
     */
    function getInforHavestPrizeOfUser(address user) external view returns(uint256) {
        uint256 amountStake = userInfor[user].amountStake;
        uint256 timeStake = userInfor[user].timeStake;
        uint256 timeNow = block.timestamp;
        uint256 timeLock = timeNow.sub(timeStake);
        uint256 prize = _calculatePrize(amountStake, timeLock);
        return prize;
    }

    /**
     * withdraw all erc20 token base balance of this contract
     */
    function withdrawToken() external onlyRole(ADMIN_ROLE) {
        uint256 balance =  IERC20(tokenBaseAddress).balanceOf(address(this));
        IERC20(tokenBaseAddress).transfer(msg.sender, balance);
    }

    /**
     * get total token reward claim
     */
    function getTotalRewardPrizeClaim() external view returns (uint256) {
        return totalRewardPrizeClaim;
    }

    /**
     * get total token reward claim
     */
    function getInforTokenEnable() external view returns (bool) {
        return isEnable;
    }
     /**
     * get total token reward claim
     */
    function getListOverallViewOfUser() external view returns (OverView [] memory) {
        uint256 indexClaim = indexPriceNotClaim[msg.sender];
        uint256 i = 0;

        OverView [] memory listView = new OverView[](countUserPrizeLock[msg.sender] - indexClaim);
        while(indexClaim < countUserPrizeLock[msg.sender]) {
            OverView memory data = OverView ({
                amount: userLockPrize[msg.sender][indexClaim].amount,
                timeUnlock: userLockPrize[msg.sender][indexClaim].timeUnlock
            });
            listView[i] = data;
            indexClaim ++;
            i++;
        }
        return listView;
    }

    function blockTimeStamp() external view returns (uint256) {
        return block.timestamp;
    }


}
