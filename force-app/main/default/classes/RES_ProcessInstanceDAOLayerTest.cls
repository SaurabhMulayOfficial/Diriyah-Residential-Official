@isTest
private class RES_ProcessInstanceDAOLayerTest {

    @isTest
    static void queries_returnEmptyWithoutApprovals() {
        Account acc = new Account(Name = 'RES PI DAO Test Account');
        insert acc;
        Set<Id> ids = new Set<Id>{ acc.Id };
        RES_ProcessInstanceDAOLayer dao = new RES_ProcessInstanceDAOLayer();

        Assert.areEqual(0, dao.getPendingWorkItemsByTargetIds(ids, 'Account').size());
        Assert.areEqual(0, dao.getApprovalHistoryByTargetIds(ids).size());
        Assert.areEqual(0, dao.getApprovalWorkItems(ids, 'Nobody').size());
        Assert.areEqual(0, dao.getApprovalWorkItemByRelatedRecordIds(ids).size());
        Assert.areEqual(0, dao.getInProgressApprovalSubmissionsByRelatedRecordIds(ids).size());
    }

    @isTest
    static void queries_handleEmptyInput() {
        RES_ProcessInstanceDAOLayer dao = new RES_ProcessInstanceDAOLayer();
        Assert.areEqual(0, dao.getApprovalWorkItemByRelatedRecordIds(new Set<Id>()).size());
        Assert.areEqual(0, dao.getInProgressApprovalSubmissionsByRelatedRecordIds(null).size());
    }
}
