@isTest
public class RES_SetSLAEndDateTimeOnApprovalItemTest {
    @isTest
    public static void testApproval(){
        Test.startTest();
        List<RES_SetSLAEndDateTimeOnApprovalItem.Input> inputs = new List<RES_SetSLAEndDateTimeOnApprovalItem.Input>();
        List<RES_SetSLAEndDateTimeOnApprovalItem.Output> outputs = new List<RES_SetSLAEndDateTimeOnApprovalItem.Output>();
        RES_SetSLAEndDateTimeOnApprovalItem.Input inputObj = new RES_SetSLAEndDateTimeOnApprovalItem.Input();
        inputObj.businessHours = 8;
        inputObj.numberOfBusinessDays = 2;
        inputs.add(inputObj);
        outputs = RES_SetSLAEndDateTimeOnApprovalItem.setSLAEndDateTimeOnApprovalWorkItem(inputs);
        if(!outputs.isEmpty()){
			Assert.isNotNull(outputs[0].slaEndDate, 'slaEndDate should not be null');
        }
        Test.stopTest();
    }
}