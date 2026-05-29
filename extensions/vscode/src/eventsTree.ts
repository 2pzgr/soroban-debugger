import * as vscode from 'vscode';

export interface SorobanEvent {
    sequence: number;
    kind: string;
    message: string;
    caller?: string;
    function?: string;
    call_depth?: number;
    storage_key?: string;
    storage_value?: string;
    address?: string;
}

type EventTreeNode = EventItem | EventItemDetail;

export class EventsTreeDataProvider implements vscode.TreeDataProvider<EventTreeNode> {
    private _onDidChangeTreeData: vscode.EventEmitter<EventTreeNode | undefined | null | void> = new vscode.EventEmitter<EventTreeNode | undefined | null | void>();
    readonly onDidChangeTreeData: vscode.Event<EventTreeNode | undefined | null | void> = this._onDidChangeTreeData.event;

    private events: SorobanEvent[] = [];

    constructor() {}

    refresh(events: SorobanEvent[]): void {
        this.events = events;
        this._onDidChangeTreeData.fire();
    }

    getTreeItem(element: EventTreeNode): vscode.TreeItem {
        return element;
    }

    getChildren(element?: EventTreeNode): Thenable<EventTreeNode[]> {
        if (element instanceof EventItem) {
            return Promise.resolve(element.getDetails());
        } else {
            return Promise.resolve(this.events.map(event => new EventItem(event)));
        }
    }
}

class EventItem extends vscode.TreeItem {
    constructor(public readonly event: SorobanEvent) {
        super(
            `[${event.sequence}] ${event.kind}: ${event.function || ''}`,
            vscode.TreeItemCollapsibleState.Collapsed
        );
        this.description = event.message;
        this.tooltip = `${event.kind}\n${event.message}`;
        this.contextValue = 'event';
        
        // Add icons based on event kind
        switch (event.kind.toLowerCase()) {
            case 'diagnostic':
                this.iconPath = new vscode.ThemeIcon('info');
                break;
            case 'functioncall':
            case 'crosscontractcall':
                this.iconPath = new vscode.ThemeIcon('call-outgoing');
                break;
            case 'storageread':
                this.iconPath = new vscode.ThemeIcon('database');
                break;
            case 'storagewrite':
                this.iconPath = new vscode.ThemeIcon('save');
                break;
            case 'authorization':
                this.iconPath = new vscode.ThemeIcon('shield');
                break;
            default:
                this.iconPath = new vscode.ThemeIcon('symbol-event');
        }
    }

    getDetails(): EventItemDetail[] {
        const details: EventItemDetail[] = [
            new EventItemDetail('Kind', this.event.kind),
            new EventItemDetail('Message', this.event.message)
        ];

        if (this.event.function) details.push(new EventItemDetail('Function', this.event.function));
        if (this.event.caller) details.push(new EventItemDetail('Caller', this.event.caller));
        if (this.event.call_depth !== undefined) details.push(new EventItemDetail('Depth', this.event.call_depth.toString()));
        if (this.event.storage_key) details.push(new EventItemDetail('Storage Key', this.event.storage_key));
        if (this.event.storage_value) details.push(new EventItemDetail('Storage Value', this.event.storage_value));
        if (this.event.address) details.push(new EventItemDetail('Address', this.event.address));

        return details;
    }
}

class EventItemDetail extends vscode.TreeItem {
    constructor(label: string, value: string) {
        super(`${label}: ${value}`, vscode.TreeItemCollapsibleState.None);
        this.contextValue = 'eventDetail';
    }
}
