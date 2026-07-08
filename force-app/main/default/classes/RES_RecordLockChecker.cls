/**
 * @ Class Name     : RES_RecordLockChecker
 * @ Description    : This class is used to check if a record is locked or not.
 * @ Author			: Nikhil Takawale
 */
public with sharing class RES_RecordLockChecker {
    
    @InvocableMethod(label = 'Check Record Lock Status')
    public static List<Output> checkRecordLock(List<Input> inputs) {
        
        List<Output> results = new List<Output>();
        
        for(Input input : inputs){
            Output out 		= new Output();
            out.isLocked 	= Approval.isLocked(input.recordId);
            results.add(out);
        }
        
        return results;
    }
    
    public class Input {
        @InvocableVariable(required = true)
        public Id recordId;
    }
    
    public class Output {
        @InvocableVariable
        public Boolean isLocked;
    }
}