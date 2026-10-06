import { createElement } from '@lwc/engine-dom';
import IntegrationSync from 'c/integrationSync';

jest.mock(
    '@salesforce/apex/RES_IntegrationSyncController.fireIntegrationEvents',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-integration-sync', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('renders the submit button', () => {
        const element = createElement('c-integration-sync', { is: IntegrationSync });
        document.body.appendChild(element);
        expect(element.shadowRoot.querySelector('button.submit')).not.toBeNull();
    });
});
