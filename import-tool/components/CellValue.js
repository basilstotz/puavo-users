
import React from "react";
import PureComponent from "./PureComponent";
import R from "ramda";

import {onEnterKey} from "../utils";
import ColumnTypes, {ReactColumnType} from "../ColumnTypes";

import {Role, RoleSelector} from "./Role";
import {LegacyRole, LegacyRoleSelector} from "./LegacyRole";
import {SchoolChange} from "./School";


export class CellValueInput extends PureComponent {

    componentDidMount() {
        if (this.refs.input) {
            const el = React.findDOMNode(this.refs.input);
            el.select();
        }
    }

    render() {
        const passProps = R.omit(["columnType", "onSelect"], this.props);

        switch(this.props.columnType.id) {
        case ColumnTypes.legacy_role.id:
            return <LegacyRoleSelector {...passProps} />;
        case ColumnTypes.role.id:
            return <RoleSelector {...passProps} />;
        case ColumnTypes.change_school.id:
            return <SchoolChange {...passProps} />;
        default:
            return (
                <input
                    {...passProps}
                    ref="input"
                    onKeyUp={onEnterKey(this.props.onSelect)}
                    className="ColumnTypeSelector-default-value-input"
                    type="text"
                    placeholder="Default"
                />
            );
        }
    }
}


CellValueInput.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
    onSelect: React.PropTypes.func.isRequired,
    columnType: ReactColumnType.isRequired,
};

export class CellValue extends PureComponent {
    render() {
        switch(this.props.columnType.id) {
        case ColumnTypes.legacy_role.id:
            return <LegacyRole id={this.props.value} />;
        case ColumnTypes.role.id:
            return <Role value={this.props.value} />;
        default:
            return <span>{this.props.value}</span>;
        }
    }
}

CellValue.propTypes = {
    value: React.PropTypes.string.isRequired,
    columnType: ReactColumnType.isRequired,
};