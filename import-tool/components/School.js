
import React from "react";
import PureComponent from "react-pure-render/component";


export class SchoolChange extends PureComponent {

    onChange() {
        this.props.onChange({target: {value: !this.props.value}});
    }

    render() {
        return (
            <label>
                <input type="checkbox" checked={this.props.value} onChange={this.onChange.bind(this)} />
                Siirrä kouluun
            </label>
        );
    }
}

SchoolChange.propTypes = {
    value: React.PropTypes.bool.isRequired,
    onChange: React.PropTypes.func.isRequired,
};

