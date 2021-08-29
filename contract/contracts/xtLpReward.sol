//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;


import "./util/SafeMath.sol";
import "./util/EnumerableSet.sol";
import "./util/Context.sol";
import "./util/IERC20.sol";
import "./util/Address.sol";
import "./util/ERC20.sol";
import "./util/Ownable.sol";
import "./util/SafeERC20.sol";
import "./util/DelegateERC20.sol";

interface IXT is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}

interface IMasterChefHeco {
    function pending(uint256 pid, address user) external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;
}

contract XTPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _multLP;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. XTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that XTs distribution occurs.
        uint256 accXTPerShare; // Accumulated XTs per share, times 1e12.
        uint256 accMultLpPerShare; //Accumulated multLp per share
        uint256 totalAmount;    // Total amount of current pool deposit.
    }

    // The xt Token!
    IXT public xt;
    // XT tokens created per block.
    uint256 public PerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    // pid corresponding address
    mapping(address => uint256) public LpOfPid;
    // Control mining
    bool public paused = false;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    uint256 public totalMiningXT;
    // The block number when XT mining starts.
    uint256 public startBlock;
 
    // How many blocks are halved
    uint256 public decayPeriod = 120960; //7*24*720   5s one block
    uint256 public decayRatio ;//= 970;//3%
    uint256 []public decayTable;
    
    address constant public ABEYToken = address(1);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetPause(bool _pause);
    event SetXTPerBlock(uint256 _amount);
    event SetDecayRatio(uint256 _ratio);
    event SetDecoyPeriod(uint256 _block);

    constructor(
        IXT _xt,
        uint256 _PerBlock, //42
        uint256 _startBlock,
        uint256 _decayRatio  //970
    ) public {
        xt = _xt;
        PerBlock = _PerBlock;
        startBlock = _startBlock;
        decayRatio = _decayRatio;
     	decayTable.push(_PerBlock); 

     	for(uint256 i=0;i<32;i++) {
     		decayTable.push(decayTable[i].mul(decayRatio).div(1000));
     	}
    }

    function setDecayPeriod(uint256 _block) public onlyOwner {
        decayPeriod = _block;

        emit SetDecoyPeriod(_block);
    }

	function setDecayRatio(uint256 _ratio) public onlyOwner {
		require(_ratio<1000,"ratio should less than 1000");
        decayRatio = _ratio;

        emit SetDecayRatio(_ratio);
    }

    // Set the number of XT produced by each block
    function setXTPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        PerBlock = _newPerBlock;

        emit SetXTPerBlock(_newPerBlock);
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function setPause() public onlyOwner {
        paused = !paused;

        emit SetPause(paused);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(address(_lpToken) != address(0), "_lpToken is the zero address");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
            poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accXTPerShare : 0,
            accMultLpPerShare : 0,
            totalAmount : 0
        }));
        LpOfPid[address(_lpToken)] = poolLength() - 1;
    }

    // Update the given pool's XT allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner  validatePoolByPid(_pid){
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    function phase(uint256 blockNumber) public view returns (uint256) {
        if (decayPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(decayPeriod);
        }
        return 0;
    }

    function rewardV(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        require(_phase<decayTable.length,"phase not ready");
        return decayTable[_phase];
    }

	function batchPrepareRewardTable(uint256 spareCount) public returns (uint256) {
		require(spareCount<64,"spareCount too large , must less than 64");
        uint256 _phase = phase(block.number);
        if( _phase.add(spareCount) >= decayTable.length){
        	uint256 loop = _phase.add(spareCount).sub(decayTable.length);
	        for(uint256 i=0;i<=loop;i++) {
	        	uint256 lastDecayValue = decayTable[decayTable.length-1];
	     		decayTable.push(lastDecayValue.mul(decayRatio).div(1000));
	     	}
        }
        return decayTable[_phase];
    }

    function safePrepareRewardTable(uint256 blockNumber)  internal returns (uint256) {
        uint256 _phase = phase(blockNumber);       
        if( _phase >= decayTable.length){
        	uint256 lastDecayValue = decayTable[decayTable.length-1];
	     	decayTable.push(lastDecayValue.mul(decayRatio).div(1000));
        }
        return decayTable[_phase];
    }

    function getXTBlockRewardV(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        while (n < m) {
            n++;
            uint256 r = n.mul(decayPeriod).add(startBlock);
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(rewardV(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(rewardV(block.number)));
        return blockReward;
    }

    function safeGetXTBlockReward(uint256 _lastRewardBlock) public returns (uint256) {
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        while (n < m) {
            n++;
            uint256 r = n.mul(decayPeriod).add(startBlock);
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(safePrepareRewardTable(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(safePrepareRewardTable(block.number)));
        return blockReward;
    }


    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public  validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply =getPoolTotalSupply(_pid);
        
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        uint256 blockReward = safeGetXTBlockReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return;
        }
        uint256 xtReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        bool minRet = xt.mint(address(this), xtReward);
        totalMiningXT = totalMiningXT.add(xtReward);
        if (minRet) {
            pool.accXTPerShare = pool.accXTPerShare.add(xtReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // View function to see pending XTs on frontend.
    function pending(uint256 _pid, address _user) external view validatePoolByPid(_pid) returns (uint256) {
        return pendingReward(_pid, _user);
    }

    
    function pendingReward(uint256 _pid, address _user) private view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accXTPerShare = pool.accXTPerShare;
        uint256 lpSupply = getPoolTotalSupply(_pid);
        if (user.amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getXTBlockRewardV(pool.lastRewardBlock);
                uint256 xtReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accXTPerShare = accXTPerShare.add(xtReward.mul(1e12).div(lpSupply));
                return user.amount.mul(accXTPerShare).div(1e12).sub(user.rewardDebt);
            }
            if (block.number == pool.lastRewardBlock) {
                return user.amount.mul(accXTPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        return 0;
    }

    function getPoolTotalSupply(uint256 _pid) view validatePoolByPid(_pid) public returns(uint256 lpSupply) {
        PoolInfo storage pool = poolInfo[_pid];
        
        if(address(pool.lpToken) == ABEYToken){
            lpSupply = address(this).balance;
        }else{
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
    }
    // Deposit LP tokens to HecoPool for xt allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause payable validatePoolByPid(_pid) {
        depositXT(_pid, _amount, msg.sender);
    }

    function depositXT(uint256 _pid, uint256 _amount, address _user) private  {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accXTPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeXTTransfer(_user, pendingAmount);
            }
        }
        if (_amount > 0) {
            if(address(pool.lpToken) == ABEYToken){
                require(_amount >= msg.value,"_amount must bigget the payable value");
                if(_amount > msg.value){
                    msg.sender.transfer(_amount.sub(msg.value));
                }
            }else{
                pool.lpToken.safeTransferFrom(_user, address(this), _amount);
            }
            
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXTPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    // Withdraw LP tokens from HecoPool.
    function withdraw(uint256 _pid, uint256 _amount) public notPause validatePoolByPid(_pid){
        withdrawXT(_pid, _amount, msg.sender);
    }

    function withdrawXT(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdrawXT: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accXTPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeXTTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            if(address(pool.lpToken) == ABEYToken){
                msg.sender.transfer(_amount);
            }else{
                pool.lpToken.safeTransfer(_user, _amount);
            }
            
        }
        user.rewardDebt = user.amount.mul(pool.accXTPerShare).div(1e12);
        emit Withdraw(_user, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public  validatePoolByPid(_pid){
        emergencyWithdrawXT(_pid, msg.sender);
        
    }

    function emergencyWithdrawXT(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        if(address(pool.lpToken) == ABEYToken){
           payable(_user).transfer(amount);
        }else{
            pool.lpToken.safeTransfer(_user, amount);
        }
        
        pool.totalAmount = pool.totalAmount.sub(amount);
        emit EmergencyWithdraw(_user, _pid, amount);
    }

    // Safe XT transfer function, just in case if rounding error causes pool to not have enough XTs.
    function safeXTTransfer(address _to, uint256 _amount) internal {
        uint256 xtBal = xt.balanceOf(address(this));
        if (_amount > xtBal) {
            xt.transfer(_to, xtBal);
        } else {
            xt.transfer(_to, _amount);
        }
    }

    modifier notPause() {
        require(paused == false, "Mining has been suspended");
        _;
    }
    
    modifier validatePoolByPid(uint256 _pid){
        require(_pid < poolInfo.length-1,"Pool not exit");
        _;
    }
}