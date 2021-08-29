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
    mapping(address=>uint256) public minerSetTime;
    
    event SetMinerTime(address _addMinter,uint256 _time);
    

    constructor() public ERC20("XTToken", "XT"){
        _mint(msg.sender, preMineSupply);
    }

    // mint with max supply
    function mint(address _to, uint256 _amount) external onlyMinter override  returns (bool) {
        require (_amount.add(totalSupply()) <= maxSupply) ;
        _mint(_to, _amount);
        return true;
    }

    function addMinter(address _addMinter) public onlyOwner returns (bool) {
        require(_addMinter != address(0), "XTToken: _addMinter is the zero address");
        minerSetTime[_addMinter] = now;
        
        emit SetMinerTime(_addMinter,now);
        return EnumerableSet.add(_minters, _addMinter);
    }

    function delMinter(address _delMinter) public onlyOwner returns (bool) {
        require(_delMinter != address(0), "XTToken: _delMinter is the zero address");
        
        minerSetTime[_delMinter] = 0;
        
        emit SetMinerTime(_delMinter,0);
        return EnumerableSet.remove(_minters, _delMinter);
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

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender) && minerSetTime[msg.sender].add(172800) >= now, "caller is not the minter");
        _;
    }

}