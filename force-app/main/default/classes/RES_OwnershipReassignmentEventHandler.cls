/**
 * @ class name         : RES_OwnershipReassignmentEventHandler
 * @ description        : This class is designed to handle the Ownership Reassignment Logic.
 * @ author             : Saurabh Mulay
 */

public with sharing class RES_OwnershipReassignmentEventHandler extends RES_BaseTriggerHandler {

    protected override void afterInsert() {
        RES_OwnershipReassignmentEventService.processOwnershipReassignment((List<RES_Ownership_Reassignment_Event__e>) Trigger.new);
    }
}