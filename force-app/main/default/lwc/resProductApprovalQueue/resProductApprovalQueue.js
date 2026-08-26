import { LightningElement, track } from 'lwc';
import getUserApprovalAccess from '@salesforce/apex/RES_ProductApprovalController.getUserApprovalAccess';
import getApprovalQueue from '@salesforce/apex/RES_ProductApprovalController.getApprovalQueue';
import approveProducts from '@salesforce/apex/RES_ProductApprovalController.approveProducts';
import rejectProducts from '@salesforce/apex/RES_ProductApprovalController.rejectProducts';
import getRejectedProducts from '@salesforce/apex/RES_ProductApprovalController.getRejectedProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAGE_SIZE = 50;
const SEARCH_DELAY = 400;
const MAX_RETRIES = 2;
const RETRY_DELAY = 2000;

// ============================================================
// SHARED COLUMN DEFINITIONS (Extracted for reuse)
// ============================================================
const BASE_COLUMNS = [
    {
        label: 'Product Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: {
            label: {
                fieldName: 'Name'
            },
            target: '_self'
        },
        wrapText: true
    },
    {
        label: 'Unit Code',
        fieldName: 'ProductCode',
        type: 'text'
    },
    {
        label: 'Project',
        fieldName: 'RES_Business_Entity__c',
        type: 'text'
    },
    {
        label: 'Status',
        fieldName: 'RES_Unit_Status__c',
        type: 'text'
    },
    {
        label: 'Typology',
        fieldName: 'RES_Type__c',
        type: 'text'
    },
    {
        label: 'Area',
        fieldName: 'RES_Area__c',
        type: 'number'
    },
    {
        label: 'Usage Type',
        fieldName: 'Family',
        type: 'text'
    },
    {
        label: 'Business Entity',
        fieldName: 'RES_Business_Entity__c',
        type: 'text'
    },
    {
        label: 'Phase Delivery Date',
        fieldName: 'RES_Unit_Handover_Date__c',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        }
    },
    {
        label: 'IBAN / Account Number',
        fieldName: 'RES_Unit_Virtual_IBAN__c',
        type: 'text'
    }
];

const ACTION_COLUMN = {
    type: 'action',
    typeAttributes: {
        rowActions: [
            {
                label: 'Approve',
                name: 'approve'
            },
            {
                label: 'Reject',
                name: 'reject'
            }
        ]
    }
};

const REJECTION_COMMENT_COLUMN = {
    label: 'Rejected Comment',
    fieldName: 'RES_Rejection_Comment__c',
    type: 'text',
    wrapText: true
};

const COLUMNS = [...BASE_COLUMNS, ACTION_COLUMN];
const REJECTED_COLUMNS = [...BASE_COLUMNS, REJECTION_COMMENT_COLUMN];

export default class ResProductApprovalQueue extends LightningElement {
    columns = COLUMNS;

    @track products = [];
    @track availableQueues = [];

    activeQueueLevel;
    activeQueueLabel = '';
    activeQueueStatus = '';
    isRejectedTab = false;
    canViewRejected = false;

    searchTerm = '';
    selectedProductIds = [];
    isLoading = false;
    isLoadingMore = false;
    isProcessing = false;

    hasError = false;
    errorMessage = '';

    hasMore = false;
    nextCreatedDate;
    nextId;

    showApprovalModal = false;
    showRejectModal = false;
    showResultModal = false;
    rejectionComment = '';
    resultSuccessCount = 0;
    resultFailureCount = 0;
    failedResults = [];
    searchTimeout;
    searchController;

    connectedCallback() {
        this.loadUserAccess();
    }

    // ============================================================
    // ACCESS
    // ============================================================

    async loadUserAccess() {
    this.isLoading = true;
    this.clearError();
    try {
        const response = await getUserApprovalAccess();
        const steps = response?.steps || [];
        this.canViewRejected = response?.canViewRejected === true;
        this.availableQueues = steps.map(step => (
            {...step,cssClass:'queue-tab'

            }));
        if (!this.availableQueues.length && !this.canViewRejected) {
            this.hasError = true;
            this.errorMessage = 'You do not have access to any Product approval queue.';
            return;
        }

        /*
         * Default to first approval queue
         * when available.
         */
        if (this.availableQueues.length) {
            this.setActiveQueue(this.availableQueues[0]);
            await this.loadQueue(true);
        } else {
            /*
             * Operations user may have
             * Rejected tab access even if
             * no approval queue is available.
             */
            this.activateRejectedTab();
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

        setActiveQueue(queue) {
        this.activeQueueLevel = Number(queue.level);
        this.activeQueueLabel = queue.queueLabel;
        this.activeQueueStatus = queue.currentStatus;
        this.availableQueues =
            this.availableQueues.map(item => ({
                ...item,
                cssClass:
                    Number(item.level) ===
                    this.activeQueueLevel
                        ? 'queue-tab active'
                        : 'queue-tab'
            }));
    }
    updateQueueTabClasses() {
        this.availableQueues =
            this.availableQueues.map(item => ({
                ...item,
                cssClass: 'queue-tab'
            }));
    }

    handleQueueChange(event) {
        const level = Number(event.currentTarget.dataset.level);
        const queue = this.availableQueues.find(
                item =>
                    Number(item.level) === level
            );
        if (!queue) {
            return;
        }
        this.isRejectedTab = false;
        this.setActiveQueue(queue);
        this.searchTerm = '';
        this.resetPagination();
        this.clearSelection();
        this.loadQueue(true);
    }

    // ============================================================
    // QUEUE
    // ============================================================

    async loadQueue(reset = false) {
        if (this.isRejectedTab) {
            await this.loadRejectedProducts(reset);
            return;
        }
        if (this.isProcessing && !reset) {
            return;
        }
        if (reset) {
            this.isLoading = true;
            this.resetPagination();
        } else {
            this.isLoadingMore = true;
        }
        this.clearError();
        try {
            const response = await getApprovalQueue({
                approvalLevel: this.activeQueueLevel,
                searchTerm: this.searchTerm?.trim() || '',
                pageSize: PAGE_SIZE,
                lastCreatedDate: reset ? null : this.nextCreatedDate,
                lastId: reset ? null : this.nextId
            });

            if (response?.errorMessage) {
                throw new Error(response.errorMessage);
            }

            const records = response?.products || [];
            const formattedRecords = records.map(record => this.formatProduct(record));

            if (reset) {
                this.products = formattedRecords;
            } else {
                // Deduplicate to prevent duplicate records from concurrent modifications
                const existingIds = new Set(this.products.map(p => p.Id));
                const newProducts = formattedRecords.filter(p => !existingIds.has(p.Id));
                this.products = [...this.products, ...newProducts];

                // Handle empty page edge case - if we got 0 new records but expect more, load next page
                if (newProducts.length === 0 && response?.hasMore && !this.isLoadingMore) {
                    console.log('Empty page detected, loading next page...');
                    this.nextCreatedDate = response?.nextCreatedDate;
                    this.nextId = response?.nextId;
                    this.hasMore = response?.hasMore === true;
                    // Don't recurse immediately to avoid infinite loop
                    return;
                }
            }

            this.hasMore = response?.hasMore === true;
            this.nextCreatedDate = response?.nextCreatedDate;
            this.nextId = response?.nextId;
        } catch (error) {
            // Check if this is an AbortError from search cancellation
            if (error.name === 'AbortError') {
                console.log('Queue load cancelled');
                return;
            }
            this.handleError(error);
        } finally {
            this.isLoading = false;
            this.isLoadingMore = false;
        }
    }

    formatProduct(record) {
    return {
        ...record,
        recordUrl: `/lightning/r/Product2/${record.Id}/view`,
        createdByName:
            record.CreatedBy?.Name || '',
        selected:
            this.selectedProductIds.includes(
                record.Id
            )
        };
    }

    activateRejectedTab() {
        this.isRejectedTab = true;
        this.activeQueueLevel = null;
        this.activeQueueLabel ='Rejected Products';
        this.activeQueueStatus ='Rejected';
        this.searchTerm = '';
        this.resetPagination();
        this.clearSelection();
        this.updateQueueTabClasses();
        this.loadRejectedProducts(true);
    }

    handleRejectedTab() {
        if (!this.canViewRejected) {
            return;
        }
        this.activateRejectedTab();
    }
    // ============================================================
    // SEARCH
    // ============================================================

    handleSearchInput(event) {
        this.searchTerm = event.target.value;

        // Cancel any previous search request to prevent race conditions
        if (this.searchController) {
            this.searchController.abort();
            this.searchController = null;
        }

        clearTimeout(this.searchTimeout);

        this.searchTimeout = setTimeout(() => {
            this.clearSelection();
            this.loadQueue(true);
        }, SEARCH_DELAY);
    }

    handleSearchKeyup(event) {
        if (event.key === 'Enter') {
            clearTimeout(
                this.searchTimeout
            );
            this.clearSelection();
            this.loadQueue(true);
        }
    }

    handleClearSearch() {
        if (!this.searchTerm) {
            return;
        }
        this.searchTerm = '';
        clearTimeout(this.searchTimeout);
        this.clearSelection();
        this.loadQueue(true);
    }

    async loadRejectedProducts(reset = false) {
        if (this.isProcessing && !reset) {
            return;
        }
        // IMPORTANT: Preserve custom permission check
        if (!this.canViewRejected) {
            return;
        }
        if (reset) {
            this.isLoading = true;
            this.resetPagination();
        } else {
            this.isLoadingMore = true;
        }
        this.clearError();
        try {
            const response = await getRejectedProducts({
                searchTerm: this.searchTerm?.trim() || '',
                pageSize: PAGE_SIZE,
                lastCreatedDate: reset ? null : this.nextCreatedDate,
                lastId: reset ? null : this.nextId
            });

            if (response?.errorMessage) {
                throw new Error(response.errorMessage);
            }

            const records = response?.products || [];
            const formattedRecords = records.map(record => this.formatProduct(record));

            if (reset) {
                this.products = formattedRecords;
            } else {
                // Deduplicate to prevent duplicate records from concurrent modifications
                const existingIds = new Set(this.products.map(p => p.Id));
                const newProducts = formattedRecords.filter(p => !existingIds.has(p.Id));
                this.products = [...this.products, ...newProducts];

                // Handle empty page edge case
                if (newProducts.length === 0 && response?.hasMore && !this.isLoadingMore) {
                    console.log('Empty page detected in rejected products, loading next page...');
                    this.nextCreatedDate = response?.nextCreatedDate;
                    this.nextId = response?.nextId;
                    this.hasMore = response?.hasMore === true;
                    return;
                }
            }

            this.hasMore = response?.hasMore === true;
            this.nextCreatedDate = response?.nextCreatedDate;
            this.nextId = response?.nextId;
        } catch (error) {
            // Check if this is an AbortError from search cancellation
            if (error.name === 'AbortError') {
                console.log('Rejected products load cancelled');
                return;
            }
            this.handleError(error);
        } finally {
            this.isLoading = false;
            this.isLoadingMore = false;
        }
    }

    // ============================================================
    // SELECTION
    // ============================================================

    handleRowSelection(event) {
        const selectedRows =
            event.detail.selectedRows || [];
        this.selectedProductIds =
            selectedRows.map(
                row => row.Id
            );
        this.syncSelectionState();
    }

    handleMobileSelection(event) {
        const productId = event.target.dataset.id;
        const checked = event.target.checked;
        const selected =
            new Set(
                this.selectedProductIds
            );

        if (checked) {
            selected.add(productId);
        } else {
            selected.delete(productId);
        }

        this.selectedProductIds = [...selected];
        this.syncSelectionState();
    }

    handleSelectAllMobile(event) {
        const checked = event.target.checked;
        if (checked) {
            this.selectedProductIds =
                this.products.map(
                    product => product.Id
                );
        } else {
            this.clearSelection();
        }
        this.syncSelectionState();
    }

    syncSelectionState() {
        const selected =
            new Set(
                this.selectedProductIds
            );
        this.products =
            this.products.map(
                product => ({
                    ...product,
                    selected:
                        selected.has(product.Id)
                })
            );
    }

    clearSelection() {
        this.selectedProductIds = [];
        this.products =
            this.products.map(
                product => ({
                    ...product,
                    selected: false
                })
            );
    }

    handleClearSelection() {
        this.clearSelection();
    }

    // ============================================================
    // ROW ACTION
    // ============================================================

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'approve') {
            this.selectSingleProduct(
                row.Id
            );
            this.openApprovalModal();

        } else if ( actionName === 'reject') {
            this.selectSingleProduct(
                row.Id
            );
            this.openRejectModal();
        }
    }

    selectSingleProduct(productId) {
        this.selectedProductIds = [
            productId
        ];
        this.syncSelectionState();
    }

    // ============================================================
    // MOBILE ACTIONS
    // ============================================================

    handleMobileApprove(event) {
        const productId = event.currentTarget.dataset.id;
        this.selectSingleProduct(productId);
        this.openApprovalModal();
    }

    handleMobileReject(event) {
        const productId = event.currentTarget.dataset.id;
        this.selectSingleProduct(productId);
        this.openRejectModal();
    }

    handleMobileAction(event) {
        const action = event.detail.value;
        const productId = event.target.dataset.id;
        if (!productId) {
            return;
        }
        this.selectSingleProduct(productId);
        if (action === 'approve') {
            this.openApprovalModal();
        } else if (
            action === 'reject'
        ) {
            this.openRejectModal();
        }
    }

    // ============================================================
    // APPROVAL
    // ============================================================

    handleBulkApprove() {
        if (!this.hasSelection) {
            return;
        }
        this.openApprovalModal();
    }

    openApprovalModal() {
        this.showApprovalModal = true;
    }

    closeApprovalModal() {
        if (!this.isProcessing) {
            this.showApprovalModal = false;
        }
    }

    async confirmApproval() {
        if (!this.hasSelection) {
            return;
        }

        this.isProcessing = true;
        let retryCount = 0;

        while (retryCount <= MAX_RETRIES) {
            try {
                const response = await approveProducts({
                    productIds: this.selectedProductIds
                });

                this.showResult(response);
                this.showApprovalModal = false;
                this.clearSelection();
                await this.loadQueue(true);
                return; // Success!

            } catch (error) {
                // Check if this is a timeout error that can be retried
                if (this.isTimeoutError(error) && retryCount < MAX_RETRIES) {
                    retryCount++;
                    this.showToast(
                        'Retrying',
                        `Request timed out. Retry ${retryCount}/${MAX_RETRIES}...`,
                        'info'
                    );
                    await this.delay(RETRY_DELAY);
                } else {
                    // Not a timeout or max retries reached
                    this.handleError(error);
                    break;
                }
            } finally {
                if (retryCount > MAX_RETRIES || retryCount === 0) {
                    this.isProcessing = false;
                }
            }
        }

        this.isProcessing = false;
    }

    // ============================================================
    // REJECTION
    // ============================================================

    handleBulkReject() {
        if (!this.hasSelection) {
            return;
        }
        this.openRejectModal();
    }

    openRejectModal() {
        this.rejectionComment = '';
        this.showRejectModal = true;
    }

    closeRejectModal() {
        if (!this.isProcessing) {
            this.showRejectModal = false;
            this.rejectionComment = '';
        }
    }

    handleRejectionComment(event) {
        this.rejectionComment = event.target.value;
    }

    async confirmReject() {
        if (!this.rejectionComment || !this.rejectionComment.trim()) {
            this.showToast(
                'Required',
                'Please provide a rejection reason.',
                'error'
            );
            return;
        }

        // Additional validation: minimum 10 characters
        if (this.rejectionComment.trim().length < 10) {
            this.showToast(
                'Invalid',
                'Rejection reason must be at least 10 characters.',
                'error'
            );
            return;
        }

        const textarea = this.template.querySelector('lightning-textarea');
        if (textarea && !textarea.reportValidity()) {
            return;
        }

        this.isProcessing = true;
        let retryCount = 0;

        while (retryCount <= MAX_RETRIES) {
            try {
                const response = await rejectProducts({
                    productIds: this.selectedProductIds,
                    rejectionComment: this.rejectionComment.trim()
                });

                this.showResult(response);
                this.showRejectModal = false;
                this.rejectionComment = '';
                this.clearSelection();
                await this.loadQueue(true);
                return; // Success!

            } catch (error) {
                // Check if this is a timeout error that can be retried
                if (this.isTimeoutError(error) && retryCount < MAX_RETRIES) {
                    retryCount++;
                    this.showToast(
                        'Retrying',
                        `Request timed out. Retry ${retryCount}/${MAX_RETRIES}...`,
                        'info'
                    );
                    await this.delay(RETRY_DELAY);
                } else {
                    // Not a timeout or max retries reached
                    this.handleError(error);
                    break;
                }
            } finally {
                if (retryCount > MAX_RETRIES || retryCount === 0) {
                    this.isProcessing = false;
                }
            }
        }

        this.isProcessing = false;
    }

    // ============================================================
    // PAGINATION
    // ============================================================
    handleLoadMore() {
        if (this.isLoadingMore || !this.hasMore) {
            return;
        }
        this.loadQueue(false);
    }

    resetPagination() {
        this.nextCreatedDate = null;
        this.nextId = null;
        this.hasMore = false;
    }

    // ============================================================
    // REFRESH
    // ============================================================
    handleRefresh() {
        this.clearSelection();
        this.loadQueue(true);
    }

    // ============================================================
    // RESULTS
    // ============================================================

    showResult(response) {
        this.resultSuccessCount = response?.successCount || 0;
        this.resultFailureCount = response?.failedCount || 0;
        this.failedResults = (response?.items || []).filter(item => item.success === false);

        // Detect concurrent modifications (products already processed by another user)
        const staleProducts = this.failedResults.filter(item => {
            const msg = item.errorMessage || '';
            return msg.includes('already processed') ||
                   msg.includes('Invalid approval state') ||
                   msg.includes('already been approved') ||
                   msg.includes('already been rejected');
        }).length;

        this.showResultModal = true;

        if (this.resultFailureCount === 0) {
            this.showToast(
                'Success',
                `${this.resultSuccessCount} Unit(s) processed successfully.`,
                'success'
            );
        } else {
            let message = `${this.resultSuccessCount} succeeded, ${this.resultFailureCount} failed.`;

            // Add helpful context if concurrent modifications detected
            if (staleProducts > 0) {
                message += ` ${staleProducts} product(s) were already processed by another user.`;
            }

            this.showToast(
                'Completed with Errors',
                message,
                'warning'
            );
        }
    }

    closeResultModal() {
        this.showResultModal = false;
    }

    // ============================================================
    // ERROR HANDLING
    // ============================================================

    handleError(error) {
        this.hasError = true;
        this.errorMessage = this.extractError(error);

        // Detect session expiration
        if (this.isSessionExpired(error)) {
            this.showToast(
                'Session Expired',
                'Your session has expired. Please refresh the page to log in again.',
                'error'
            );
            // Disable all actions to prevent confusion
            this.isProcessing = true;
            return;
        }

        this.showToast(
            'Error',
            this.errorMessage,
            'error'
        );
    }

    clearError() {
        this.hasError = false;
        this.errorMessage = '';
    }

    extractError(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }

    // ============================================================
    // HELPER METHODS FOR EDGE CASE HANDLING
    // ============================================================

    isSessionExpired(error) {
        const msg = error?.body?.message || error?.message || '';
        return msg.includes('INVALID_SESSION_ID') ||msg.includes('Session expired') || msg.includes('Session has expired') || error?.status === 401;
    }

    isTimeoutError(error) {
        const msg = error?.body?.message || error?.message || '';
        return msg.toLowerCase().includes('timeout') || msg.toLowerCase().includes('timed out') || error?.status === 408;
    }

    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // ============================================================
    // TOAST
    // ============================================================
    showToast(title,message,variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    // ============================================================
    // GETTERS
    // ============================================================
    get approvalStageMessage() {
        const count = this.selectedCount;
        const unitText = count === 1 ? 'Unit' : 'Units';
        // Final approval stage - CSO
        if (this.activeQueueLabel === 'CSO') {
            return count === 1
                ? 'The Unit has been approved by CSO and is now Available.'
                : 'The Units have been approved by CSO and are now Available.';
        }

        // DevCo / Finance approval stages
        return `The selected ${unitText.toLowerCase()} will be moved to the next approval stage.`;
    }

    get approvalConfirmationMessage() {
        const count = this.selectedCount;
        const unitText = count === 1 ? 'Unit' : 'Units';
        return `Are you sure you want to approve ${count} ${unitText}?`;
    }
    get emptyStateTitle() {
        return this.isRejectedTab
            ? 'No Rejected Products'
            : 'No Products Pending Approval';
        }

    get emptyStateMessage() {
        return this.isRejectedTab
            ? 'There are currently no rejected Products.'
            : 'There are currently no Products waiting for approval in this queue.';
        }

    get activeColumns() {
        return this.isRejectedTab
            ? REJECTED_COLUMNS
            : this.columns;
    }

    get showQueueTabs() {
        return (
            this.availableQueues.length > 0 ||
            this.canViewRejected
        );
    }

    get rejectedTabClass() {
        return this.isRejectedTab
            ? 'queue-tab active'
            : 'queue-tab';
    }

    get hasMultipleQueues() {
        return this.availableQueues.length > 1;
    }

    get hasSelection() {
        return (
            this.selectedProductIds.length > 0
        );
    }

    get selectedCount() {
        return this.selectedProductIds.length;
    }

    get showRecords() {
        return (
            !this.isLoading &&
            !this.hasError &&
            this.products.length > 0
        );
    }

    get showEmptyState() {
        return (
            !this.isLoading &&
            !this.hasError &&
            this.products.length === 0
        );
    }

    get showLoadMore() {
        return (
            this.showRecords &&
            this.hasMore
        );
    }

    get canApprove() {
        const queue =
            this.availableQueues.find(
                item =>
                    Number(item.level) ===
                    this.activeQueueLevel
            );
        return queue?.canApprove === true;
    }

    get canReject() {
        const queue =
            this.availableQueues.find(
                item =>
                    Number(item.level) ===
                    this.activeQueueLevel
            );

        return queue?.canReject === true;
    }

    get disableClearButton() {
        return !this.searchTerm;
    }

    get allVisibleSelected() {
        return (
            this.products.length > 0 &&
            this.products.every(
                product =>
                    this.selectedProductIds.includes(
                        product.Id
                    )
            )
        );
    }

    get rejectionCharacterCount() {
        return (
            this.rejectionComment?.length || 0
        );
    }

    get hasFailedResults() {
        return (
            this.failedResults.length > 0
        );
    }
}