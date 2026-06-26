import { LightningElement } from 'lwc';
import getConvertedLeads from '@salesforce/apex/RES_ConvertedLeadController.getConvertedLeads';

const DEFAULT_PAGE_SIZE = 20;
const SEARCH_DELAY = 300;

export default class ResConvertedLeads extends LightningElement {
    heading = 'Converted Leads';
    isLoading = true;

    leads = [];
    pageNumber = 1;
    pageSize = DEFAULT_PAGE_SIZE;
    searchKey = '';
    totalCount = 0;
    totalPages = 1;
    pageInputValue = '1';

    _searchTimeout;

    pageSizeOptions = [
        { label: '20', value: '20' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '200', value: '200' }
    ];

    columns = [
        {
            label: 'Lead Name',
            fieldName: 'leadUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'name' },
                target: '_blank'
            }
        },
        { label: 'Owner', fieldName: 'ownerName', type: 'text' },
        { label: 'Status', fieldName: 'statusLabel', type: 'text' },
        { label: 'Company', fieldName: 'company', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Mobile', fieldName: 'mobilePhone', type: 'phone' },
        { label: 'Lead Source', fieldName: 'leadSourceLabel', type: 'text' },
        {
            label: 'Created Date',
            fieldName: 'createdDate',
            type: 'date',
            typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
        },
        {
            label: 'Converted Date',
            fieldName: 'convertedDate',
            type: 'date',
            typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
        }
    ];

    connectedCallback() {
        this.loadData();
    }

    get hasRecords() {
        return this.leads.length > 0;
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get startRecord() {
        if (this.totalCount === 0) return 0;
        return (this.pageNumber - 1) * this.pageSize + 1;
    }

    get endRecord() {
        return Math.min(this.pageNumber * this.pageSize, this.totalCount);
    }

    get recordRangeLabel() {
        if (this.totalCount === 0) return '0 records';
        return `${this.startRecord}–${this.endRecord} of ${this.totalCount}`;
    }

    get showPagination() {
        return !this.isLoading && this.totalCount > 0;
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        clearTimeout(this._searchTimeout);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimeout = setTimeout(() => {
            this.pageNumber = 1;
            this.pageInputValue = '1';
            this.loadData();
        }, SEARCH_DELAY);
    }

    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.detail.value, 10);
        this.pageNumber = 1;
        this.pageInputValue = '1';
        this.loadData();
    }

    handleFirstPage() {
        if (!this.isFirstPage) {
            this.pageNumber = 1;
            this.pageInputValue = '1';
            this.loadData();
        }
    }

    handlePrevPage() {
        if (!this.isFirstPage) {
            this.pageNumber -= 1;
            this.pageInputValue = String(this.pageNumber);
            this.loadData();
        }
    }

    handleNextPage() {
        if (!this.isLastPage) {
            this.pageNumber += 1;
            this.pageInputValue = String(this.pageNumber);
            this.loadData();
        }
    }

    handleLastPage() {
        if (!this.isLastPage) {
            this.pageNumber = this.totalPages;
            this.pageInputValue = String(this.pageNumber);
            this.loadData();
        }
    }

    handlePageInputChange(event) {
        this.pageInputValue = event.target.value;
    }

    handlePageInputKeydown(event) {
        if (event.key === 'Enter') {
            this.navigateToPage();
        }
    }

    handlePageInputBlur() {
        this.navigateToPage();
    }

    navigateToPage() {
        let page = parseInt(this.pageInputValue, 10);
        if (isNaN(page) || page < 1) page = 1;
        if (page > this.totalPages) page = this.totalPages;
        this.pageInputValue = String(page);
        if (page !== this.pageNumber) {
            this.pageNumber = page;
            this.loadData();
        }
    }

    loadData() {
        this.isLoading = true;
        getConvertedLeads({
            pageNumber: this.pageNumber,
            pageSize: this.pageSize,
            searchKey: this.searchKey
        })
            .then(result => {
                this.heading = result.heading || 'Converted Leads';
                this.leads = (result.leads || []).map(lead => ({
                    ...lead,
                    leadUrl: '/' + lead.id
                }));
                this.totalCount = result.totalCount || 0;
                this.totalPages = result.totalPages || 1;
                this.pageNumber = result.pageNumber || 1;
                this.pageSize = result.pageSize || DEFAULT_PAGE_SIZE;
                this.pageInputValue = String(this.pageNumber);
            })
            .catch(error => {
                this.leads = [];
                this.totalCount = 0;
                this.totalPages = 1;
                console.error('Error loading converted leads', JSON.stringify(error));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}
