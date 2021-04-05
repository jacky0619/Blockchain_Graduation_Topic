pragma solidity >=0.4.22 <0.6.0;
contract TradeHandler {
    address payable private seller;
    address payable private carrier;
    address payable private buyer;
    address private owner;
    address private company;
    address private manufacture;
    uint private purchasePrice;
    uint private carrierFee;
    
     struct ownerhistory {   //存放所有曾經的擁有者
        address  ownerID;
    }
    mapping  (uint => ownerhistory) private ownerhistories;
    uint private numallowner=0;
    
    uint private productstatus; //存商品的新舊  1:新  2:舊
    uint private trialperiod; //若商品是舊則賣家輸入鑑賞期 新則預設為7天
    
    //為了退貨存的原本賣家及買家address
    address private  returnseller;
    address payable private returnbuyer;

    int private BuyerPurchaseWay;//判斷如果買家選面交 跳過貨運
    int private Sellerpurchaseway;//0:只可面交 1:只可貨運 2:貨運面交皆可
    bool private flag=false;//true:可被購買 false:不可購買
    
    uint private nowtime;//暫存現在時間
    bool private result=false;
    //bool private manufacturecheck=false;//紀錄製造商確認與否
    
    enum WaitingFor {          //一般化交易流程 
        OwnerCreate,           //擁有者創建完成
        BuyerEscrowPayment,    //買家已付款
        SellerRelease,         //賣家已出貨
        CarrierReceive,        //貨運已拿貨
        CarrierArrive,         //貨運已到貨
        BuyerGet,              //買家已拿貨
        BuyerAccept,           //買家已確認
        Completed,             //完成
        NotCompleted           //買家覺得商品有問題
    }
    WaitingFor private state;
    
     
    enum ReturnProcess {   //退貨的狀態流程
        BuyerInitiate,     //買家發起
        SellerConfirm,     //賣家是否同意
        BuyerRelease,      //買家出貨
        CarrierReceive,    //貨運拿貨
        CarrierArrive,     //貨運到貨
        SellerGet,         //賣家拿貨
        SellerAccept,      //賣家確認
        Completed,         //完成
        NotCompleted       //賣家覺得商品有問題
    }
    ReturnProcess private returnprocess;


    enum OwnerShip { //判別現在擁有者是否交出擁有權
        isowner,
        iscontract
    }
    OwnerShip private ownership;
  
    
    //**********************************************修飾函數********************************************
    modifier pricecondition(bool _condition) {
        require(_condition,"price is wrong.");
        
        _;
    }
    modifier condition(bool _condition) {
        require(_condition,"bool is wrong.");
        
        _;
    }
    modifier onlySeller() {
        require(
            msg.sender == seller,
            "Only seller can call this."
        );
        _;
    }
     modifier onlyReturnSeller() {
        require(
            msg.sender == returnseller,
            "Only returnseller can call this."
        );
        _;
    }
    modifier onlyBuyer() {
        require(
            msg.sender == buyer,
            "Only buyer can call this."
        );
        _;
    }
    modifier onlyReturnBuyer() {
        require(
            msg.sender == returnbuyer,
            "Only returnbuyer can call this."
        );
        _;
    }
      modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only owner can call this."
        );
        _;
    }
     modifier onlycarrier() {
        require(
            msg.sender == carrier,
            "Only carrier can call this."
        );
        _;
    }
    modifier onlyManufacture() {
        require(
            msg.sender == manufacture,
            "Only manufacture can call this."
        );
        _;
    }
    modifier inState(WaitingFor _state){  //檢查state是否符合
        require(
            state == _state,
            "Invalid state."
        );
        _;
    }
    modifier OwnerShipCheck(OwnerShip _ownership){  //檢查擁有權是否被扣留
        require(
            ownership == _ownership,
            "Contract is the owner."
        );
        _;
    }
     modifier ReturnProcessCheck(ReturnProcess _returnprocess){  //檢查退貨的流程
        require(
            returnprocess == _returnprocess,
            "Invalid returnprocess."
        );
        _;
    }
    function getResult() public view returns (bool){ //拿到買賣家按正確與否
          return (result);
      }

    //************************************公司創建及全額付款購買********************************************
    constructor (address _manufacture) public 
    {
        seller =msg.sender;
        owner =msg.sender;
        ownerhistories[numallowner].ownerID=owner;
        numallowner++;
        ownership=OwnerShip.isowner;
        company = msg.sender;
        manufacture=_manufacture;
        nowtime =now;
        state=WaitingFor.Completed;
    }
    
    function OwnerCreate( address _buyer, address _carrier, uint _carrierFee, uint _purchasePrice, uint _productstatus,uint _trialperiod)
    public payable
    onlyOwner
    inState(WaitingFor.Completed)
    OwnerShipCheck(OwnerShip.isowner)
     {  
        purchasePrice=_purchasePrice;
        seller = msg.sender;
        owner = msg.sender;
        buyer  = address(uint160(address(_buyer)));
        carrier =address(uint160(address(_carrier)));
        carrierFee=_carrierFee;
        state=WaitingFor.OwnerCreate;
        
        productstatus= _productstatus;
        trialperiod= _trialperiod;
        nowtime=now;//創建完後把當下時間存在nowtime中
        ownership=OwnerShip.iscontract;//選擇完賣家及交出擁有權
     }
     
    function BuyerPay() //等待買家付款
    public 
    inState(WaitingFor.OwnerCreate)
    pricecondition(msg.value == ( purchasePrice  + carrierFee))
    onlyBuyer
    payable{
        if(carrier==address(uint160(address(0)))&&carrierFee==0){ //代表面交或實體店面
            state=WaitingFor.BuyerGet;
        }
        else
        state = WaitingFor.BuyerEscrowPayment;
        
        nowtime=now;
      
    }
    
    //****************************賣家開放讓商品可購買及買家付押金購買function**************************
    struct requester {
        int   Buyerpurchaseway; // 0:面交 1:貨運 
        address payable requesterID;
    }
    mapping  (uint => requester) private requesters;
    uint private numrequester=0;
    
    function Sell(uint _purchasePrice,int _sellerpurchaseway, uint _productstatus,uint _trialperiod)
    inState(WaitingFor.Completed)
    onlyOwner
    public
    {
        purchasePrice=_purchasePrice;
        Sellerpurchaseway=_sellerpurchaseway;
        productstatus= _productstatus;
        trialperiod=_trialperiod;
        flag=true;

    }
    
    function Buy(int _buyerpurchaseway)
    public
    pricecondition(msg.value == ( purchasePrice * 1/10 ))
    condition(flag)
    payable
    
    { 
        requesters[numrequester].Buyerpurchaseway=_buyerpurchaseway;
        requesters[numrequester].requesterID=msg.sender;
        
        if(Sellerpurchaseway<2)
            if(Sellerpurchaseway!=requesters[numrequester].Buyerpurchaseway)
                revert("購買方式錯誤");
            
        numrequester++;
    }
    
    function chooseBuyer(uint _num ,address _carrier,uint _carrierFee) public  //賣家選擇一個買家 之後交出擁有權
    onlyOwner
    {    
         uint  Num;//存賣家選擇的買家號碼
         Num=_num;
         buyer=requesters[Num].requesterID ;
         BuyerPurchaseWay=requesters[Num].Buyerpurchaseway;//買家購買方式會刪所以先存
           
         for(uint i=0;i<numrequester;i++)
         {
             if(i!=Num)
                 requesters[i].requesterID.transfer(purchasePrice * 1/10);
            
             delete(requesters[i]);//選完即刪除所有買家資料     
         }
        
         flag =false;
         ownership=OwnerShip.iscontract;//選擇完買家及交出擁有權
         seller = msg.sender;
         owner = msg.sender;
         carrier =address(uint160(address(_carrier)));
         carrierFee=_carrierFee;
         state=WaitingFor.OwnerCreate;
         numrequester=0;//已選擇完買家數量初始
         nowtime=now;//創建完後把當下時間存在nowtime中
    }
    
     //***********************押金流程(買家付餘額)****************************
  
    function WaitingBuyerPay() //等待買家付款
    public 
    inState(WaitingFor.OwnerCreate)
    pricecondition(msg.value == (  purchasePrice * 9/10 + carrierFee))
    onlyBuyer
    payable{
        
        if(BuyerPurchaseWay==0)//如果面交跳過貨運
        state=WaitingFor.BuyerGet;
        else
        state = WaitingFor.BuyerEscrowPayment;
        
        nowtime=now;
    }
    //***************買家已付款後押金及全額的接續流程(有貨運)*************
    
    function WaitingSellerRelease (bool _result)//等待賣家出貨
    public
    onlySeller
    inState(WaitingFor.BuyerEscrowPayment)
    {
        result =_result;
        if(result == true)
        state=WaitingFor.SellerRelease;
        
        result=false;
        nowtime=now;
    }
    
    function WaitingCarrierReceive (bool _result)//等待貨運收貨
    public
    onlycarrier
    inState(WaitingFor.SellerRelease){
        
        result=_result;
        if(result == true)
        state=WaitingFor.CarrierReceive;
        
        result=false;
        nowtime=now;
    }
    
    function WaitingCarrierArrive (bool _result)//等待貨運到貨
    public
    onlycarrier
    inState(WaitingFor.CarrierReceive){
        
        result=_result;
        if(result == true)
        state=WaitingFor.CarrierArrive;
        
        result=false;
        nowtime=now;
    }
    
    function WaitingBuyerGet (bool _result)//等待買家拿貨
    public
    onlyBuyer
    inState(WaitingFor.CarrierArrive){
        
        result=_result;
        if(result == true)
        state=WaitingFor.BuyerGet;
        
        carrier.transfer(carrierFee);
        result=false;
        nowtime=now;
    }
    //***************若為面交則買家直接跳到這個function來執行**************
    
    function WaitingBuyerAccept (bool _result)//等待買家確認
    public
    onlyBuyer
    inState(WaitingFor.BuyerGet)
    {
        result=_result;
        if(result==true){
        state=WaitingFor.BuyerAccept;
        
        completed();//完成且錢發送
        reset();//重置
        }
        else{
          state=WaitingFor.NotCompleted;
           
        }
        
        //退貨時用到
        returnbuyer=buyer;
        returnseller=seller;
        
        nowtime=now;
        result=false;
    }
    
    function completed() public//等待交易完成
    inState(WaitingFor.BuyerAccept)
    {
        seller.transfer(purchasePrice);
        owner = buyer;
        ownerhistories[numallowner].ownerID=owner;
        numallowner++;
        ownership=OwnerShip.isowner;
        state=WaitingFor.Completed;
            
        //退貨時用到
        returnbuyer=buyer;
        returnseller=seller;
    }
    
    function reset() public {
        seller = address(uint160(address(0)));
        buyer =address(uint160(address(0)));
        carrier =address(uint160(address(0)));
        carrierFee = 0;
        purchasePrice =0;
    } 
     
    //*****************************時間的判斷及function***************************
    modifier onlyAfter(uint  _time){ //現在的時間超過設定(預期)時間才可呼叫
          require(
          now > _time,"time is not yet"); _; }
    
     modifier onlyBefore( uint  _time){ //現在的時間小於設定(規定)時間才可呼叫
          require(
          now < _time,"time is over"); _; }
     
     
    function SellerOverChoose()//買家付完押金後賣家遲遲沒有選擇出一個買家 則買家可呼叫還回押金
    public
    
    {   
        for(uint i=0;i<numrequester;i++){
            if(msg.sender==requesters[i].requesterID){
                msg.sender.transfer(purchasePrice * 1/10);
                delete(requesters[i]);
            }
        }
        
    }
    
    function BuyerOverPay()//賣家創建完合約 買家超過時間未付款or未付餘額時賣家可呼叫
    public 
    inState(WaitingFor.OwnerCreate)
    onlyAfter(nowtime + 5 minutes)
    onlySeller
    {
        seller.transfer(purchasePrice * 1/10);
        state=WaitingFor.Completed;
    }
    
    
    function SellererOverRelease()//買家已付款 賣家超過時間未出貨時買家可呼叫
    public 
    inState(WaitingFor.BuyerEscrowPayment)
    onlyAfter(nowtime + 5 minutes)
    onlyBuyer
    {
        buyer.transfer(purchasePrice);
        reset(); //沒有complete擁有權就會扣留在合約內
        state=WaitingFor.Completed;
    }
    
    function BuyerOverGet()//買家超過時間未拿貨時賣家可呼叫
    public 
    inState(WaitingFor.BuyerEscrowPayment)
    onlyAfter(nowtime + 5 minutes)
    onlySeller
    {
        seller.transfer(purchasePrice * 1/10);
        buyer.transfer(purchasePrice * 9/10);
        carrier.transfer(carrierFee);
        state=WaitingFor.Completed;
    }
    
    function BuyerOverAccept()//買家超過時間未確認商品時賣家可呼叫
    public 
    inState(WaitingFor.BuyerGet)
    onlyAfter(nowtime + 5 minutes)
    onlySeller
    {
        seller.transfer(purchasePrice);
        state=WaitingFor.Completed;
    } 
       
    //***************************************************退貨流程****************************************************************
    
    function BuyerWantReturn(address _carrier) //買家發起退貨
    public
    onlyReturnBuyer
    onlyBefore(nowtime + trialperiod *1 days)//一手7天內可退
    
     {  
        carrier =address(uint160(address(_carrier)));
        
        if(productstatus==1)//如果商品狀態為新則跳過賣家是否同意
        returnprocess=ReturnProcess.SellerConfirm;
        else 
        returnprocess=ReturnProcess.BuyerInitiate;
        
        nowtime=now;
       
     }
     
    function SellerAgree(bool _result)//賣家是否同意
    public
    onlyReturnSeller
    ReturnProcessCheck(ReturnProcess.BuyerInitiate)
    {
        result=_result;
        if(result==true)
        returnprocess=ReturnProcess.SellerConfirm;
        
        
        nowtime=now;
        result=false;    
        
    }
    
    function BuyerRelease (bool _result)//買家是否出貨且付貨運費
    public payable
    pricecondition(msg.value == 1 ether)//判斷貨運費
    ReturnProcessCheck(ReturnProcess.SellerConfirm)
    {
        result=_result;
        if(result==true)
        returnprocess=ReturnProcess.BuyerRelease;
        
        
        nowtime=now;
        result=false;
    }
    
    function CarrierReceive (bool _result)//等待貨運收貨
    public
    onlycarrier
    ReturnProcessCheck(ReturnProcess.BuyerRelease)
    {
        
        result=_result;
        if(result == true)
        returnprocess=ReturnProcess.CarrierReceive;
        
        result=false;
        nowtime=now;
    }
    
    function CarrierArrive (bool _result)//等待貨運到貨
    public
    onlycarrier
    ReturnProcessCheck(ReturnProcess.CarrierReceive)
    {
        
        result=_result;
        if(result == true)
        returnprocess=ReturnProcess.CarrierArrive;
        
        result=false;
        nowtime=now;
    } 
    
    function SellerGet (bool _result) //等待賣家拿貨
    public
    onlyReturnSeller
    ReturnProcessCheck(ReturnProcess.CarrierArrive)
    {
        result=_result;
        if(result == true)
        returnprocess=ReturnProcess.SellerGet;
        
        carrier.transfer(1 ether);
        result=false;
        nowtime=now;
    }
    
    function SellerAccept (bool _result) //等待賣家確認
    public
    onlyReturnSeller
    ReturnProcessCheck(ReturnProcess.SellerGet)
    {
        result=_result;
        if(result == true){
        returnprocess=ReturnProcess.SellerAccept;
        
        ReturnComplete;
        ReturnReset;
        }
        else{ //雙方走其他途徑協調
        returnprocess=ReturnProcess.NotCompleted;
        }
        
        result=false;
        nowtime=now;
    }
    
    function ReturnComplete()
    ReturnProcessCheck(ReturnProcess.SellerAccept)
    public
    {
        returnprocess=ReturnProcess.Completed;
        
        if(state == WaitingFor.NotCompleted){
            returnbuyer.transfer(purchasePrice);
        }
        
        owner = returnseller;
        ownership=OwnerShip.isowner;
    }
    
    function ReturnReset()
    ReturnProcessCheck(ReturnProcess.Completed)
    public
    {
        returnseller = address(uint160(address(0)));
        returnbuyer = address(uint160(address(0)));
        carrier = address(uint160(address(0)));
    }
    
}