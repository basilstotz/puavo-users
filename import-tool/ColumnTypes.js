
import R from "ramda";

const required = true;

const ColumnTypes = [
    {name: "First name", attribute: "first_name", id: "first_name", required},
    {name: "Last name", attribute: "last_name", id: "last_name", required},
    {name: "Email", attribute: "email", id: "email"},
    {name: "Username", attribute: "username", id: "username", required},
    {name: "User type", attribute: "roles", id: "user_type", required},
    {name: "Unkown", id: "unknown"},
    // {name: "Role (legacy)", attribute: "legacy_role"},
];

const toMapId = R.reduce((map, type) => R.assoc(type.id, type, map), {});

export const REQUIRED_COLUMNS = R.filter(R.propEq("required", true), ColumnTypes);

export default toMapId(ColumnTypes);