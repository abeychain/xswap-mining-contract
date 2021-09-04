// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./util/SafeMath.sol";
import "./util/EnumerableSet.sol";
import "./util/Context.sol";
import "./util/IERC20.sol";
import "./util/Address.sol";

import "./util/ERC20.sol";

import "./util/Ownable.sol";
import "./util/DelegateERC20.sol";

interface IXT is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}

contract XTToken is DelegateERC20,IXT, Ownable {
    uint256 private constant preMineSupply = 200000000 * 1e18; 
    uint256 private constant maxSupply =    1200000000 * 1e18;     // the total supply

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;
    
    
    // multi signature list 
    // M/n  multi signatrue
    mapping(address => uint256) public signListIndex; // address => index sign list 
    mapping(uint256 => address) public signList; // index => add sign list 
    uint256 internal m_Num; // m/n signatrue  m
    uint256 internal n_Num; // m/n signatrue  n
    
    // Multi state 
    enum msState{ Empty,Pending,Complete,Failed }
    
    // Multi signatrue struct 
    struct MultiSign {
        msState ms_state;  // state of this Sign
        mapping(address => bool) ms_isSign; // judge the signList is or not sign 
        address[]   ms_signList; // sign List for interface
        address ms_currentMiner;
        uint256 ms_startTime; // MultiSign create time 
        uint256 ms_endTime; // this sign end time 
        uint256 ms_updataTime; //this is updata time 
    }
    
    MultiSign  public addMultiSignInfo;
    MultiSign  public delMultiSignInfo;
    
    mapping(address=>uint256) public minerSetTime;
    
    event SetMinerTime(address _addMinter,uint256 _time);
    

    constructor(uint256 numConfirm,address[] memory memberList) public ERC20("XTToken", "XT"){
        _mint(msg.sender, preMineSupply);
        
        require(numConfirm <= memberList.length ,"numConfirm number too bigger");
        require(numConfirm >= 2 && numConfirm < 50,"numConfirm not in range");
        n_Num = numConfirm;
        
        for(uint256 i = 0; i < memberList.length; i++){
            addSignMember(memberList[i]);
        }
    }

    // mint with max supply
    function mint(address _to, uint256 _amount) external onlyMinter override  returns (bool) {
        require (_amount.add(totalSupply()) <= maxSupply) ;
        _mint(_to, _amount);
        return true;
    }

    function addMinterInternal(address _addMinter) internal  returns (bool) {
        require(_addMinter != address(0), "XTToken: _addMinter is the zero address");
        
        minerSetTime[_addMinter] = now;
        
        emit SetMinerTime(_addMinter,now);
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinterInternal(address _delMinter) internal  returns (bool) {
        require(_delMinter != address(0), "XTToken: _delMinter is the zero address");
        
        minerSetTime[_delMinter] = 0;
        emit SetMinerTime(_delMinter,0);
        return EnumerableSet.remove(_minters, _delMinter);
    }
    
    
    function add_delMiner(address _miner, uint256 _dealLine,bool isAddMiner) public OnlyInSignList{
        require(_miner != address(0), "XTToken: _miner is the zero address");
        if(isAddMiner){
            require(!isMinter(_miner),"alread is miner");
        }else{
            require(isMinter(_miner)," miner not miner");
        }
        
        
        MultiSign storage currentSign = isAddMiner? addMultiSignInfo : delMultiSignInfo;
        
        msState currentState = addMultiSignInfo.ms_state;
        if(currentState != msState.Complete || currentState != msState.Failed){
            currentSign.ms_state = msState.Empty;
            currentState = msState.Empty;
        }
        
        if(currentState == msState.Empty){
            currentSign.ms_state = msState.Pending;
            currentSign.ms_startTime = now;
            currentSign.ms_endTime = now.add(_dealLine);
            currentSign.ms_currentMiner = _miner;
        }
        
        if(!currentSign.ms_isSign[msg.sender]){
            currentSign.ms_isSign[msg.sender] = true;
            currentSign.ms_signList.push(msg.sender);
        }
        
        checkProposal(isAddMiner);
        
    }
    
    
    function checkProposal(bool isAddMiner) internal {
        
         MultiSign storage currentSign = isAddMiner? addMultiSignInfo : delMultiSignInfo;
         
         require(currentSign.ms_state == msState.Pending,"not in pending this proposal");
         
         // check time 
         uint256 nowTime = now;
         currentSign.ms_updataTime = nowTime;
         if(nowTime > currentSign.ms_endTime){
             currentSign.ms_state = msState.Failed;
             return;
         }

         //check sign number 
         if(currentSign.ms_signList.length >= n_Num){
            executeProposal(isAddMiner); 
         }
    }
    
    function executeProposal(bool isAddMiner) internal {
        MultiSign storage currentSign = isAddMiner? addMultiSignInfo : delMultiSignInfo;
        require(currentSign.ms_state == msState.Pending,"not in pending this proposal");
        
       // currentSign.ms_
        
        currentSign.ms_state = msState.Failed;
        bool res ;
        if(isAddMiner){
            res  = addMinterInternal(currentSign.ms_currentMiner);
        }else{
            res  = delMinterInternal(currentSign.ms_currentMiner);
        }
        
        if(res){
            currentSign.ms_state = msState.Complete;
            
            
            
        }
        
        uint256 len = currentSign.ms_signList.length;
        for(uint256 i = 0 ; i< len; i++){
            currentSign.ms_isSign[currentSign.ms_signList[i]] = false;
        }
        delete currentSign.ms_signList;
    }
    
    function getMultiSignLength(bool isAdd) public view returns(uint256){
        return isAdd ? addMultiSignInfo.ms_signList.length :  delMultiSignInfo.ms_signList.length;
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinter(uint256 _index) public view onlyOwner returns (address){
        require(_index <= getMinterLength() - 1, "XTToken: index out of bounds");
        return EnumerableSet.at(_minters, _index);
    }
    
    
    function addSignToList(address mAddr) external OnlyThisContract {
        addSignMember(mAddr);
    }
    
    function addSignMember(address mAddr) internal {
        require(mAddr != address(0),"error sign address");
        require(signListIndex[mAddr] == 0,"alread in sign lists");
        m_Num++;
        signListIndex[mAddr] = m_Num;
        signList[m_Num] = mAddr;
    }
    
    function removeSignAddrToList(address mAddr) external OnlyThisContract{
        require(isInSignList(mAddr),"not in the sign list");
        if(signList[m_Num] != mAddr){
            signList[signListIndex[mAddr]] = signList[m_Num];
        }
        m_Num--;
        require(n_Num <= m_Num, " nconfirm  number too bigger ");
        signListIndex[mAddr] = 0;
    }
    
    function updataNconfirmNum(uint256 nNum) external OnlyThisContract{
        require(nNum <= m_Num ,"nconfirm  number too bigger");
        n_Num = nNum;
    }
    
    function isInSignList(address mAddr) public view returns(bool){
        return signListIndex[mAddr] > 0 ;
    }

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender) && minerSetTime[msg.sender].add(86400) <= now, "caller is not the minter or not time");
        _;
    }
    
    modifier OnlyInSignList(){
        require(isInSignList(msg.sender),"not in sign list");
        _;
    }
    
    modifier OnlyThisContract(){
        require(msg.sender == address(this),"not exec address" );
        _;
    }

}