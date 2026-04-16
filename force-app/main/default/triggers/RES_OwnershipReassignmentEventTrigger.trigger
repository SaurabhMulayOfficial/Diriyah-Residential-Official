trigger RES_OwnershipReassignmentEventTrigger on RES_Ownership_Reassignment_Event__e (after insert) {
    new RES_OwnershipReassignmentEventHandler().run();
}