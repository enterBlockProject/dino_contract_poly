const { time } = require('@openzeppelin/test-helpers');

const Distributor = artifacts.require('distributor');
const Dino = artifacts.require('Dino');
const MockERC20 = artifacts.require('MockERC20');

contract('Distributor test', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.dino = await Dino.new(dev, dev, {from: dev});
    });

    context('With ERC/LP token added to the field', () => {
        beforeEach(async () => {
            this.lp = await MockERC20.new('LPToken', 'LP', '10000000000', { from: minter });
            await this.lp.transfer(alice, '1000', { from: minter });
            await this.lp.transfer(bob, '1000', { from: minter });
            await this.lp.transfer(carol, '1000', { from: minter });
            this.lp2 = await MockERC20.new('LPToken2', 'LP2', '10000000000', { from: minter });
            await this.lp2.transfer(alice, '1000', { from: minter });
            await this.lp2.transfer(bob, '1000', { from: minter });
            await this.lp2.transfer(carol, '1000', { from: minter });
        });

        it('should give out dinos only after farming time', async () => {
            this.distributor = await Distributor.new(
                this.dino.address,
                '100',
                '1000000000000000000',
                '400',
                '3',
                { from: alice });
            await this.dino.setMinter(this.distributor.address, {from: dev});

            await this.distributor.addRewardPool(this.lp.address, '100', {from: dev});
            await this.lp.approve(this.distributor.address, '1000', { from: bob });
            await this.distributor.deposit(0, '100', { from: bob });
            await time.advanceBlockTo('89');
            await this.distributor.deposit(0, '0', { from: bob }); // block 90

            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '0');
            await time.advanceBlockTo('94');
            await this.distributor.claim(0, { from: bob }); // block 95
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '0');
            await time.advanceBlockTo('99');
            await this.distributor.claim(0, { from: bob }); // block 100
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '0');
            await time.advanceBlockTo('100');
            await this.distributor.claim(0, { from: bob }); // block 101
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '97');
            await time.advanceBlockTo('104');
            await this.distributor.claim(0, { from: bob }); // block 105
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '485');
            assert.equal((await this.dino.totalSupply()).valueOf(), '500');
        });

        it('should not distribute dinos if no one deposit', async () => {
            this.distributor = await Distributor.new(
                this.dino.address,
                '200',
                '1000000000000000000',
                '400',
                '3',
                { from: alice });
            await this.dino.setMinter(this.distributor.address, {from: dev});

            await this.distributor.addRewardPool(this.lp.address, '100', {from: dev});
            await this.lp.approve(this.distributor.address, '1000', { from: bob });
            await time.advanceBlockTo('199');
            assert.equal((await this.dino.totalSupply()).valueOf(), '0');
            await time.advanceBlockTo('204');
            assert.equal((await this.dino.totalSupply()).valueOf(), '0');
            await time.advanceBlockTo('209');
            await this.distributor.deposit(0, '10', { from: bob }); // block 210
            assert.equal((await this.dino.totalSupply()).valueOf(), '0');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '0');
            assert.equal((await this.dino.balanceOf(dev)).valueOf(), '0');
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '990');
            await time.advanceBlockTo('219');
            await this.distributor.withdraw(0, '10', { from: bob }); // block 220

            assert.equal((await this.dino.totalSupply()).valueOf(), '1000');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '970');
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '1000');
        });

        it('should distribute dinos properly for each staker', async () => {
            this.distributor = await Distributor.new(
                this.dino.address,
                '300',
                '1000000000000000000',
                '400',
                '0',
                { from: alice });
            await this.dino.setMinter(this.distributor.address, {from: dev});

            await this.distributor.addRewardPool(this.lp.address, '100', {from: dev});
            await this.lp.approve(this.distributor.address, '1000', { from: alice });
            await this.lp.approve(this.distributor.address, '1000', { from: bob });
            await this.lp.approve(this.distributor.address, '1000', { from: carol });
            // Alice deposits 10 LPs at block 310
            await time.advanceBlockTo('309');
            await this.distributor.deposit(0, '10', { from: alice });
            // Bob deposits 20 LPs at block 314
            await time.advanceBlockTo('313');
            await this.distributor.deposit(0, '20', { from: bob });
            // Carol deposits 30 LPs at block 318
            await time.advanceBlockTo('317');
            await this.distributor.deposit(0, '30', { from: carol });
            await time.advanceBlockTo('319')
            await this.distributor.deposit(0, '10', { from: alice });

            assert.equal((await this.dino.totalSupply()).valueOf(), '566');
            assert.equal((await this.dino.balanceOf(alice)).valueOf(), '566');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '0');
            assert.equal((await this.dino.balanceOf(carol)).valueOf(), '0');

            await time.advanceBlockTo('329')
            await this.distributor.withdraw(0, '5', { from: bob });

            assert.equal((await this.dino.totalSupply()).valueOf(), '1185');
            assert.equal((await this.dino.balanceOf(alice)).valueOf(), '566');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '619');
            assert.equal((await this.dino.balanceOf(carol)).valueOf(), '0');


            // Alice withdraws 20 LPs at block 340.
            // Bob withdraws 15 LPs at block 350.
            // Carol withdraws 30 LPs at block 360.
            await time.advanceBlockTo('339')
            await this.distributor.withdraw(0, '20', { from: alice });
            await time.advanceBlockTo('349')
            await this.distributor.withdraw(0, '15', { from: bob });
            await time.advanceBlockTo('359')
            await this.distributor.withdraw(0, '30', { from: carol });

            assert.equal((await this.dino.totalSupply()).valueOf(), '4999');
            assert.equal((await this.dino.balanceOf(alice)).valueOf(), '1159');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '1183');
            assert.equal((await this.dino.balanceOf(carol)).valueOf(), '2657');
            // All of them should have 1000 LPs back.
            assert.equal((await this.lp.balanceOf(alice)).valueOf(), '1000');
            assert.equal((await this.lp.balanceOf(bob)).valueOf(), '1000');
            assert.equal((await this.lp.balanceOf(carol)).valueOf(), '1000');
        });

        it('should give proper dinos allocation to each pool', async () => {
            this.distributor = await Distributor.new(
                this.dino.address,
                '400',
                '1000000000000000000',
                '400',
                '0',
                { from: alice });
            await this.dino.setMinter(this.distributor.address, {from: dev});

            await this.lp.approve(this.distributor.address, '1000', { from: alice });
            await this.lp2.approve(this.distributor.address, '1000', { from: bob });
            // Add first LP to the pool with allocation 1
            await this.distributor.addRewardPool(this.lp.address, '10', {from : dev});
            // Alice deposits 10 LPs at block 410
            await time.advanceBlockTo('409');
            await this.distributor.deposit(0, '10', { from: alice });
            // Add LP2 to the pool with allocation 2 at block 420
            await time.advanceBlockTo('419');
            await this.distributor.addRewardPool(this.lp2.address, '20', {from: dev});
            // Alice should have 10*1000 pending reward
            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '1000');


            // Bob deposits 10 LP2s at block 425
            await time.advanceBlockTo('424');
            await this.distributor.deposit(1, '5', { from: bob });
            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '1166');


            await time.advanceBlockTo('430');
            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '1333');
            assert.equal((await this.distributor.rewardAmount(1, bob)).valueOf(), '333');
        });

        it('should stop giving bonus after the bonus period ends', async () => {
            this.distributor = await Distributor.new(
                this.dino.address,
                '600',
                '10',
                '400',
                '0',
                { from: alice });
            await this.dino.setMinter(this.distributor.address, {from: dev});

            await this.lp.approve(this.distributor.address, '1000', { from: alice });
            await this.lp.approve(this.distributor.address, '1000', { from: bob });
            await this.distributor.addRewardPool(this.lp.address, '1', {from: dev});
            // Alice deposits 10 LPs at block 590
            await time.advanceBlockTo('605');
            await this.distributor.deposit(0, '10', { from: alice });
            await this.distributor.deposit(0, '10', { from: bob });

            await time.advanceBlockTo('615');

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '47500000000000000000'); //10+10/2*3+9/2*5
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '37500000000000000000'); //10/2*3+9/2*5

            await time.advanceBlockTo('625');

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '90000000000000000000'); //10+10/2*3+9/2*10+8/2*5
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '80000000000000000000'); //10/2*3+9/2*10+8/2*5

            await time.advanceBlockTo('635');

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '127500000000000000000'); //10+10/2*3+9/2*10+8/2*10+7/2*5
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '117500000000000000000'); //10/2*3+9/2*10+8/2*10+7/2*5

            await time.advanceBlockTo('645');

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '160000000000000000000'); //10+10/2*3+9/2*10+8/2*10+7/2*10+6/2*5
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '150000000000000000000'); //10/2*3+9/2*10+8/2*10+7/2*10+6/2*5

            await time.advanceBlockTo('655');

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '175000000000000000000'); //10+10/2*3+9/2*10+8/2*10+7/2*10+6/2*10
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '165000000000000000000'); //10/2*3+9/2*10+8/2*10+7/2*10+6/2*10

            await this.distributor.claim(0, { from: alice });
            await this.distributor.claim(0, { from: bob });

            assert.equal((await this.distributor.rewardAmount(0, alice)).valueOf(), '0');
            assert.equal((await this.distributor.rewardAmount(0, bob)).valueOf(), '0');
            assert.equal((await this.dino.balanceOf(alice)).valueOf(), '175000000000000000000');
            assert.equal((await this.dino.balanceOf(bob)).valueOf(), '165000000000000000000');
        });

    });
});