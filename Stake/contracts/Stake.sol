// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Stake is Ownable, ReentrancyGuard {
    using SafeMath for uint;

    // BSC 链 USDC 地址
    IERC20 public usdc = IERC20(0x8965349fb649A33a30cbFDa057D8eC2C48AbE2A2);

    // struct Order {
    //     address user;
    //     uint amount;
    //     uint updateTime;  //最近更新时间，如果已经计算过收益之后变为计算收益的时间
    //     uint endTime;       
    //     uint amountOfDevice;
    //     uint yieldPerDay;
    // }

    struct Order {
        address user;
        uint amount;
        uint updateTime;
        uint endTime;
        uint current_totalDevice;
        uint current_totalYeild;
    }

    Order[] orders;

    uint constant expend_15 = 6.0975e19;    // 121.95 USDC / 2
    uint constant expend_30 = 1.2195e20;    // 121.95 USDC

    //总收益
    uint private totalYeild;
    //总矿机数
    uint private totalDevice;

    uint private yeildOfAdmin;

    //用户的收益
    mapping(address => uint) yieldOfUser;
    //用户的本金
    mapping(address => uint) balanceOf;
    //orders中对应的订单在用户列表中的位置
    mapping(uint => uint) orderInUserList;
    //用户拥有的订单数量
    mapping(address => uint) orderOfUser;
    //用户所拥有的订单的位置
    mapping(address => mapping(uint => uint)) indexOfUser;

    event Depoist(address user, uint amount, uint current_time, uint8 lockDuration);
    event GetReward(address user, uint amount);
    event Withdraw(address user, uint amount);
    event CountReward();

    constructor(uint _totalYeild, uint _totalDevice) {
        totalYeild = _totalYeild;
        totalDevice = _totalDevice;
    }

    /**
     * @dev 质押
     * @param _amount 质押的 USDC 数量
     * @param _invitation 上级邀请人
     * @param _method 为 false 表示质押 15 天，true 表示质押 30 天
     */
    function depoist(uint _amount, address _invitation, bool _method) public returns() {
        (uint current_totoalDevice, uint current_totalYeild) = _getTotalDeviceAndYield();
        require(current_totoalDevice * current_totalYeild != 0, "Both TotalDevice and TotalYeild can't be zero");

        usdc.transferFrom(msg.sender, address(this), _amount);

        Order memory newOrder;
        if(_invitation == address(0)) {
            if(_method) {
                newOrder = Order(msg.sender, _amount, block.timestamp, block.timestamp + 30 days, current_totoalDevice, current_totalYeild);
            } else {
                newOrder = Order(msg.sender, _amount, block.timestamp, block.timestamp + 15 days, current_totoalDevice, current_totalYeild);
            }
        } else { 
            yieldOfUser[_invitation] += _amount / 100;;
            if(_method) {    
                newOrder = Order(msg.sender, _amount, totalYeild, block.timestamp.add(day_30), amountOfDevice, totalYeild.div(totalDevice).div(30));
            } else {
                newOrder = Order(msg.sender, _amount, totalYeild, block.timestamp.add(day_15), amountOfDevice, totalYeild.div(totalDevice).div(15));
            }
        }
        orders.push(newOrder);
        balanceOf[msg.sender] += _amount;
        uint orderAmounts = orderOfUser[msg.sender];
        orderInUserList[orders.length - 1] = orderAmounts;
        orderOfUser[msg.sender] = orderAmounts + 1;
        indexOfUser[msg.sender][orderAmounts] = orders.length - 1;

        uint8 lockDuration = _method == true ? 30 : 15;
        emit Depoist(msg.sender, _amount, block.timestamp, lockDuration);
    }

    function getYeild() public nonReentrant {
        countYield();       
        uint amount = yieldOfUser[msg.sender];
        //余额大于50则进行转账，小于等于50就进行收益统计不转帐并激发一个统计收益事件提醒
        if(amount > 50 * 1e18) {
            uint amountUser = amount.mul(97).div(100);      // 3% 手续费
            yeildOfAdmin = yeildOfAdmin.add(amount.sub(amountUser));
            usdc.transfer(msg.sender,amountUser);
            emit GetReward(msg.sender, amountUser);
        } else {
            emit CountReward();
        }
    }

    function withdraw() public nonReentrant {
        uint amount;
        uint len = orderOfUser[msg.sender];
        for(uint i = 0; i < len; i++) {
            uint index = indexOfUser[msg.sender][i];
            Order storage order = orders[index];
            //如果到达质押时间，但未计算收益
            if(block.timestamp > order.endTime && order.updateTime < order.endTime) {
                uint time = Math.min(order.endTime, block.timestamp);
                uint yield = time.sub(order.updateTime).div(1 days).mul(order.yieldPerDay).div(2);
                order.updateTime = time;
                yieldOfUser[msg.sender] = yieldOfUser[msg.sender].add(yield);
                amount.add(order.amount);
                //更新数组
                _removeOrder(index);
            } else if (block.timestamp > order.endTime && order.updateTime == order.endTime) {//如果到达质押时间，已经计算收益
                //更新数组
                amount.add(order.amount);
                _removeOrder(index);
            }
        }
        uint amountUser = amount.mul(97).div(100);      // 3% 手续费
        yeildOfAdmin = yeildOfAdmin.add(amount.sub(amountUser));
        usdc.transfer(msg.sender, amountUser);
        emit Withdraw(msg.sender, amountUser);
    }

    //计算收益
    function countYield() internal {
        for(uint i = 0; i < orderOfUser[msg.sender]; i++) {
            uint index = indexOfUser[msg.sender][i];
            Order storage order = orders[index];
            //判断是否已经计算了收益
            if(order.updateTime == order.endTime) {
                continue;
            }
            uint time = Math.min(order.endTime, block.timestamp);
            uint yield = time.sub(order.updateTime).div(1 days).mul(order.yieldPerDay).div(2);
            order.updateTime = time;
            yieldOfUser[msg.sender] = yieldOfUser[msg.sender].add(yield);
        }
    }

    function _removeOrder(uint _indexInOrder) private {       
        //将orders数组进行更新
        Order memory lastOrder = orders[orders.length.sub(1)];
        Order memory order = orders[_indexInOrder];
        orders[_indexInOrder] = lastOrder;        
        //不对indexInUser中下架的Order进行删除，而是将用户持有的订单量减少，采用覆盖的方式进行维护
        uint index = orderInUserList[_indexInOrder];
        address user = order.user;
        indexOfUser[user][index] = indexOfUser[user][orderOfUser[user].sub(1)];
        orderOfUser[user] = orderOfUser[user].sub(1);
        //维护orderInUser
        uint lastOrderInUser = orderInUserList[orders.length.sub(1)];
        indexOfUser[lastOrder.user][lastOrderInUser] = _indexInOrder;
        orderInUserList[_indexInOrder] = lastOrderInUser;
        delete orderInUserList[orders.length.sub(1)];
        orders.pop(); 
    }

    function ckeckYeild() public view returns(uint Yeild) {
        return yieldOfUser[msg.sender];
    }

    function setTotalYeild(uint _amount) public onlyOwner() returns(bool) {
        totalYeild = _amount;
        return true;
    }

    function setTotalDevice(uint _amount) public onlyOwner() returns(bool) {
        totalDevice = _amount;
        return true;
    }

    function _getTotalDeviceAndYield() private returns (uint _totalDevice, uint _totalYield) {
        _totalDevice = totalDevice;
        _totalYeild = totalYeild;
    }

    function withdrawByAdmin(address _to) public onlyOwner() {
        uint amount = yeildOfAdmin;
        yeildOfAdmin = 0;
        usdc.transfer(_to, amount);
    }
}