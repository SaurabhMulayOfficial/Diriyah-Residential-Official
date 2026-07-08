@isTest
public class RES_RecordLockCheckerTest {
	
    @testSetup
    public static void setupData(){
        Test.startTest();
        RES_TestDataFactory.createLead('john.doe0799@gmail.com');
        Test.stopTest();
    }

	@isTest    
    public static void checkRecordLockTest(){
        Test.startTest();
        
        List<Lead> leadLst = [ SELECT Id 
                               FROM Lead 
                               WHERE Email = 'john.doe0799@gmail.com' LIMIT 1 ];
        
        if(!leadLst.isEmpty()){
            List<RES_RecordLockChecker.Input> inputs = new List<RES_RecordLockChecker.Input>();
            List<RES_RecordLockChecker.Output> outputs = new List<RES_RecordLockChecker.Output>();
            RES_RecordLockChecker.Input input = new RES_RecordLockChecker.Input();
            input.recordId = leadLst[0].Id;
			inputs.add(input);
            outputs = RES_RecordLockChecker.checkRecordLock(inputs);
            Assert.areEqual(false, outputs[0].isLocked);
        }
        
        Test.stopTest();
    }
}