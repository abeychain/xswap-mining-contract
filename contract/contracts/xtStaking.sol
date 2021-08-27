//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;


import "./util/SafeMath.sol";
import "./util/SafeERC20.sol";
import "./util/Ownable.sol";
import "./util/IERC20.sol";

interface IXT is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}

contract xtStaing is Ownable{
    
    using SafeMath for *;
    using SafeERC20 for IXT;
    
    
    IXT public xtToken;  

    mapping(uint256 => stakingPoolInfo_S) public stakingPoolInfo;//  _stakingTpye -> staking info
    mapping(uint256 => bool) isStakingType;
    mapping(address => mapping(uint256 => user_S)) public userInfo;
    
    mapping(uint256 => uint256) public totalSupply;
    
    struct user_S{
        uint256 amount; //  every epoch lock amount
        uint256 epochIndex; // epoh lock amount ,180 days,300 days epoch 
        uint256 lastUpdateRewardTime;
        uint256 reward;
        bool isKeepStaking;// if is true, next epoch stop 
        uint256 totalReward;
        uint256 changeKeepStakingTime;
    }
    
    struct stakingPoolInfo_S{
        uint256 startTime;
        uint256 currentEpoch;
        uint256 epochTimelen;
        uint256 epochRewardRate; //rwardRate this is for 180 days, and 300 days
    }
    
    event EmergencyWithdraw(address indexed _user, uint256 indexed _stakingType, uint256 _amount);
    event Deposit(address _user,uint256 _stakingType, uint256 _amount,bool _isKeepStaking);
    event Withdraw(address _user,uint256 _stakingType,uint256 _amount);
    event GetReward(address _user,uint256 _stakingType, uint256 _amount);
    event UpdateKeepStaking(address _user, uint256 _stakingType,bool _isKeepStaking);
    
    constructor(IXT _xtToken,uint256 _startTime) public{
        require(_startTime >= now,"start time must big or equle now");
        xtToken = _xtToken;
        
        init(_startTime);
    }
    
    //fallback() external payable { }
    //receive() external payable {}
    
    //15552000,31536000 this is two staking type
    function deposit(uint256 _stakingType, uint256 _amount,bool _isKeepStaking) public onlyStakingSupport(_stakingType){
        require(_amount > 0,"must big 0");
        
        user_S storage us = userInfo[msg.sender][_stakingType];
        xtToken.safeTransferFrom(msg.sender,address(this),_amount);
        
        // update reward;
        (uint256 reward ,uint256 curEpoch) = pendingReward(_stakingType,msg.sender);
        if(reward > 0){
            us.reward = reward;
        }
        stakingPoolInfo[_stakingType].currentEpoch = curEpoch;
        
        us.isKeepStaking = _isKeepStaking;
        us.lastUpdateRewardTime = now;
        us.amount = us.amount.add(_amount);
        us.changeKeepStakingTime = now;
        totalSupply[_stakingType] = totalSupply[_stakingType].add(_amount);
        
        emit Deposit(msg.sender,_stakingType,_amount,_isKeepStaking);
    }
    
    
    function withdraw(uint256 _stakingType,uint256 _amount) public{
        
        user_S storage us = userInfo[msg.sender][_stakingType];
        require(us.amount>= _amount && _amount > 0,"not enght amount");
        
        getReward(_stakingType);
        
        if(!us.isKeepStaking){
           (,uint256 nowStartime,) =getEpoch(_stakingType,now);
           require(nowStartime >= us.changeKeepStakingTime,"keepstaking time is not right");
           
           // withdraw
           us.amount = us.amount.sub(_amount);
           xtToken.safeTransfer(msg.sender,_amount);
           
           totalSupply[_stakingType] = totalSupply[_stakingType].sub(_amount);
        }
        
        emit Withdraw(msg.sender,_stakingType,_amount);
    }
    
    function getCanWithdrawAmount(uint256 _stakingType,address _user) public view returns(uint256 _amount){
        user_S memory us = userInfo[_user][_stakingType];
        if(!us.isKeepStaking){
            (,uint256 nowStartime,) =getEpoch(_stakingType,now);
            if(nowStartime >= us.changeKeepStakingTime){
                _amount = us.amount;
            }else{
                _amount = 0;
            }
        }else{
            _amount = 0;
        }
    }
    
    function getReward(uint256 _stakingType) public onlyStakingSupport(_stakingType){
        user_S storage us = userInfo[msg.sender][_stakingType];
        if(us.amount == 0 && us.reward == 0){
            return;
        }
        (uint256 reward,uint256 curEpoch) = pendingReward(_stakingType,msg.sender);
        if(reward > 0){
            if(!us.isKeepStaking){
                (,,uint256 endTime) = getEpoch(_stakingType,us.changeKeepStakingTime);
                if(now < endTime){
                    us.lastUpdateRewardTime = now;
                }else{
                    us.lastUpdateRewardTime = endTime;
                }
                
            }else{
                us.lastUpdateRewardTime = now;
            }
            us.totalReward = us.totalReward.add(reward);
            us.reward = 0;
            xtToken.mint(msg.sender,reward);
        }
        
        stakingPoolInfo[_stakingType].currentEpoch = curEpoch;
        
        emit GetReward(msg.sender,_stakingType,reward);
    }
    
    function updateKeepStaking(uint256 _stakingType,bool _isKeepStaking) public onlyStakingSupport(_stakingType){
        user_S storage us = userInfo[msg.sender][_stakingType];
        require(us.amount >0,"not lock balance");
        
        uint256 userReward;
        uint256 curEpoch;
        
        (userReward,curEpoch) = pendingReward(_stakingType,msg.sender);
        
        us.reward = userReward;
        us.lastUpdateRewardTime = now;
        us.isKeepStaking = _isKeepStaking;
        us.changeKeepStakingTime = now;
        
        stakingPoolInfo[_stakingType].currentEpoch = curEpoch;
        
        emit UpdateKeepStaking(msg.sender,_stakingType,_isKeepStaking);
    }
    
    function pendingReward(uint256 _stakingType,address _user) public view returns(uint256 _reward,uint256 _curEpoch){
        user_S memory us = userInfo[_user][_stakingType];
        stakingPoolInfo_S memory  pool = stakingPoolInfo[_stakingType];
        
        require(now >= pool.startTime && (us.lastUpdateRewardTime == 0 || us.lastUpdateRewardTime >= pool.startTime),"time not right");
        
        
        uint256 endTime;
        uint256 timeLen;
        (_curEpoch,,) = getEpoch(_stakingType,now);
        
        if(us.lastUpdateRewardTime == 0){
            return (_reward,_curEpoch);
        }
        if(us.isKeepStaking){
            timeLen = now.sub(us.lastUpdateRewardTime);
        }else{
            // only need update time to get end time
            (,,endTime) = getEpoch(_stakingType,us.changeKeepStakingTime);
            if(now < endTime  ){
                if(now > us.lastUpdateRewardTime){
                    timeLen = now.sub(us.lastUpdateRewardTime);
                }else{
                    timeLen = 0;
                }
            }else{
                timeLen = endTime.sub(us.lastUpdateRewardTime);
            }
            
        }
        
        uint256 _amount = us.amount.mul(timeLen).mul(pool.epochRewardRate).div(1e18);
        _reward =  _amount.add(us.reward);
        
    }
    
    function getEpoch(uint256 _stakingType,uint256 _time) view public returns(uint256 _epochIndex,uint256 _epochStartTime,uint256 _epochendTime){
        
        stakingPoolInfo_S memory  pool = stakingPoolInfo[_stakingType];
        if(_time == 0 || _time < pool.startTime){
            return (_epochIndex,_epochStartTime,_epochendTime);
        }
        
        uint256 epcohLen = _time.sub(pool.startTime).div(pool.epochTimelen);
        uint256 currentepoch_index;
        if(epcohLen == 0){
            _epochIndex = 1;
            _epochStartTime = pool.startTime;
            _epochendTime = pool.startTime.add(pool.epochTimelen);
            return (_epochIndex,_epochStartTime,_epochendTime);
        }
        if(epcohLen != 0 && (epcohLen > pool.currentEpoch ||  epcohLen < pool.currentEpoch)){
            if(_time.sub(pool.startTime) > epcohLen.mul(pool.epochTimelen)){
                currentepoch_index = epcohLen+1;
            }else{
                 currentepoch_index = epcohLen;
            }
        }else if(epcohLen == pool.currentEpoch){
            if(_time.sub(pool.startTime) >= pool.epochTimelen){
                currentepoch_index = pool.currentEpoch+1;
            }else{
                currentepoch_index = pool.currentEpoch;
            }
        }
        _epochIndex = currentepoch_index;
        if(_epochIndex == 1){
            _epochStartTime = pool.startTime;
            _epochendTime = pool.startTime.add(pool.epochTimelen);
        }else{
            _epochStartTime = _epochIndex.sub(1).mul(pool.epochTimelen).add(pool.startTime);
            _epochendTime = _epochIndex.mul(pool.epochTimelen).add(pool.startTime);
        }
    }
    
    
    function addStakingPool(uint256 _stakingType,uint256 _startTime,uint256 _rate) public onlyOwner{
        require(!isStakingType[_stakingType],"already add this stakingType");
        stakingPoolInfo[_stakingType] = stakingPoolInfo_S({
            startTime:_startTime,
            currentEpoch:1,
            epochTimelen:_stakingType,
            epochRewardRate: _rate
        });
        
        isStakingType[_stakingType] = true;
    }
    
    function init(uint256 _startTime) internal{
        stakingPoolInfo[15552000] = stakingPoolInfo_S({
            startTime:_startTime,
            currentEpoch:1,
            epochTimelen:15552000,
            epochRewardRate: 5*1e17.div(31536000)
        });
        
        stakingPoolInfo[31536000] = stakingPoolInfo_S({
            startTime:_startTime,
            currentEpoch:1,
            epochTimelen:31536000,
            epochRewardRate: 1*1e18.div(31536000)
        });
        
        isStakingType[15552000] = true;
        isStakingType[31536000] = true;
    }
    
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _stakingType, address _user) public onlyOwner{
        
        user_S storage user = userInfo[_user][_stakingType];
        
        uint256 amount = user.amount;
        user.amount = 0;
        user.reward = 0;
        if(amount > 0){
            xtToken.safeTransfer(_user,amount);
            totalSupply[_stakingType] = totalSupply[_stakingType].sub(amount);
        }
        emit EmergencyWithdraw(_user, _stakingType, amount);
    }
    
    modifier onlyStakingSupport(uint256 _stakingType){
        require(isStakingType[_stakingType],"only staking type");
        _;
    }
    
}
