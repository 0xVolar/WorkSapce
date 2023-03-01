// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

// 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48

contract Stake is Ownable{
    using SafeMath for uint;

    ERC20 public usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    struct Order {
        address user;
        uint amount;
        uint updateTime;  //最近更新时间，如果已经计算过收益之后变为计算收益的时间
        uint endTime;       
        uint amountOfDevice;
        uint yieldPerDay;
    }

    Order[] orders;
    uint constant day_15 = 15 days;
    uint constant day_30 = 30 days;
    uint constant expend_15 = 6.0975e19;
    uint constant expend_30 = 1.2195e20;
    uint constant expendPerDevice = 4.065e18;
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

    event Depoist(address user, uint devices);
    event GetReward(address user, uint amount);
    event Withdraw(address user, uint amount);
    event CountReward();

    constructor(uint _totalYeild, uint _totalDevice) Ownable() {
        totalYeild = _totalYeild;
        totalDevice = _totalDevice;
    }

    //_method为false时质押15天，true为质押30天
    //先将代币进行转移
    function depoist(uint _amount, address _invitation, bool _method) public returns(uint amountOfDevice) {
        usdc.transferFrom(msg.sender, address(this), _amount);
        //先更新累计的收益总和
        // update(_totalYeild, _totalDevice);
        //判断是否有邀请人，然后创建订单
        require(totalDevice != 0, "TotalDevice can't be zero");
        if(_invitation == address(0)) {
            if(_method) {
                amountOfDevice = _amount.div(expend_30);
                Order memory order = Order(msg.sender, _amount, block.timestamp, block.timestamp.add(day_30), amountOfDevice, totalYeild.div(totalDevice).div(30));
                orders.push(order);
                balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);
                uint amount = orderOfUser[msg.sender];
                orderInUserList[orders.length.sub(1)] = amount;
                orderOfUser[msg.sender] = amount.add(1);
                indexOfUser[msg.sender][amount] = orders.length.sub(1);              
                emit Depoist(msg.sender, amountOfDevice);
            } else {
                amountOfDevice = _amount.div(expend_15);
                Order memory order = Order(msg.sender, _amount, totalYeild, block.timestamp.add(day_15), amountOfDevice, totalYeild.div(totalDevice).div(15));
                orders.push(order);
                balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);
                uint amount = orderOfUser[msg.sender];
                orderInUserList[orders.length.sub(1)] = amount;
                orderOfUser[msg.sender] = amount.add(1);
                indexOfUser[msg.sender][amount] = orders.length.sub(1);
                emit Depoist(msg.sender, amountOfDevice);
            }
        } else {
            uint yeild = _amount.div(100);
            yieldOfUser[_invitation] = yieldOfUser[_invitation].add(yeild);
            if(_method) {
                //先计算邀请人获得的收益  
                amountOfDevice = _amount.sub(yeild).div(expend_30);              
                Order memory order = Order(msg.sender, _amount, totalYeild, block.timestamp.add(day_30), amountOfDevice, totalYeild.div(totalDevice).div(30));
                orders.push(order);
                balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);
                uint amount = orderOfUser[msg.sender];
                orderInUserList[orders.length.sub(1)] = amount;
                orderOfUser[msg.sender] = amount.add(1);
                indexOfUser[msg.sender][amount] = orders.length.sub(1);
                emit Depoist(msg.sender, amountOfDevice);
            } else {
                amountOfDevice = _amount.sub(yeild).div(expend_15); 
                Order memory order = Order(msg.sender, _amount, totalYeild, block.timestamp.add(day_15), amountOfDevice, totalYeild.div(totalDevice).div(15));
                orders.push(order);
                balanceOf[msg.sender] = balanceOf[msg.sender].add(_amount);
                uint amount = orderOfUser[msg.sender];
                orderInUserList[orders.length.sub(1)] = amount;
                orderOfUser[msg.sender] = amount.add(1);
                indexOfUser[msg.sender][amount] = orders.length.sub(1);
                emit Depoist(msg.sender, amountOfDevice);
            }
        }
    }

    function getYeild() public {
        countYield();       
        uint amount = yieldOfUser[msg.sender];
        //余额大于50则进行转账，小于等于50就进行收益统计不转帐并激发一个统计收益事件提醒
        if(amount > 5**19) {
            uint amountUser = amount.mul(997).div(1000);
            yeildOfAdmin = yeildOfAdmin.add(amount.sub(amountUser));
            usdc.transfer(msg.sender,amountUser);
            emit GetReward(msg.sender, amountUser);
        } else {
            emit CountReward();
        }
    }

    function withdraw() public {
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
                removeOrder(index);
            } else if (block.timestamp > order.endTime && order.updateTime == order.endTime) {//如果到达质押时间，已经计算收益
                //更新数组
                amount.add(order.amount);
                removeOrder(index);
            }
        }
        uint amountUser = amount.mul(997).div(1000);
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

    function removeOrder(uint _indexInOrder) internal {       
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

    function withdrawByAdmin(address _to) public onlyOwner() {
        uint amount = yeildOfAdmin;
        yeildOfAdmin = 0;
        usdc.transfer(_to, amount);
    }
}