
import R from "ramda";
import {updateIn} from "updeep";
import cleanDiacritics from "underscore.string/cleanDiacritics";

import {
    ADD_COLUMN,
    CHANGE_COLUMN_TYPE,
    CLEAR_AUTO_OPEN_COLUMN_EDITOR,
    DROP_COLUMN,
    DROP_ROW,
    FILL_COLUMN,
    GENERATE_USERNAME,
    SET_ACTIVE_COLUMN_TYPES,
    SET_CUSTOM_VALUE,
    SET_DEFAULT_SCHOOL,
    SET_GROUPS,
    SET_IMPORT_DATA,
    SET_LEGACY_ROLES,
    SET_ROW_STATUS,
    SET_USER_DATA,
} from "./constants";
import {AllColumnTypes} from "./ColumnTypes";
import {getCellValue, deepFreeze} from "./utils";

const initialState = deepFreeze({
    rows: [],
    rowStatus: {},
    defaultSchool: null,
    legacyRoles: [],
    groups: [],
    autoOpenColumnEditor: null,
    userCache: {},
    activeColumnTypes: AllColumnTypes,
    columns: [
        AllColumnTypes.first_name,
        AllColumnTypes.last_name,
    ],
    visibleUsernames: [],
});


const arrayToObj = R.addIndex(R.reduce)((acc, val, i) => R.assoc(i, {originalValue: val}, acc), {});
const findLongestRowLength = R.compose(R.reduce(R.max, 0), R.map(R.prop("length")));
const appendUnknownColumns = R.compose(R.flip(R.concat), R.repeat(AllColumnTypes.unknown), R.max(0));
const removeByIndex = R.remove(R.__, 1);

function reducer(state=initialState, action) {
    switch (action.type) {
    case "SET_VISIBLE_USERNAMES":
        return R.assoc("visibleUsernames", action.visibleUsernames, state);
    case SET_IMPORT_DATA:
        return R.evolve({
            columns: appendUnknownColumns(findLongestRowLength(action.data) - state.columns.length),
            rows: R.always(action.data.map(arrayToObj)),
        }, state);
    case SET_CUSTOM_VALUE:
        const value = action.value === GENERATE_USERNAME
            ? generateUsername(action.rowIndex, state)
            : action.value;

        return updateIn(["rows", action.rowIndex, action.columnIndex, "customValue"], R.trim(value), state);
    case ADD_COLUMN:
        return R.evolve({
            autoOpenColumnEditor: R.always(state.columns.length),
            columns: R.append(AllColumnTypes[action.columnType]),
        }, state);
    case CLEAR_AUTO_OPEN_COLUMN_EDITOR:
        return R.assoc("autoOpenColumnEditor", null, state);
    case DROP_ROW:
        return R.evolve({
            rows: removeByIndex(action.rowIndex),
            rowStatus: R.omit([String(action.rowIndex)]),
        }, state);
    case DROP_COLUMN:
        return R.evolve({columns: removeByIndex(action.columnIndex)}, state);
    case CHANGE_COLUMN_TYPE:
        return updateIn(["columns", action.columnIndex], R.always(AllColumnTypes[action.typeId]), state);
    case SET_ROW_STATUS:
        return updateIn(["rowStatus", action.rowIndex], R.merge(R.__, R.omit(["type"], action)), state);
    case SET_DEFAULT_SCHOOL:
        return R.assoc("defaultSchool", action.school, state);
    case SET_LEGACY_ROLES:
        return R.assoc("legacyRoles", action.legacyRoles, state);
    case SET_GROUPS:
        return R.assoc("groups", action.groups, state);
    case FILL_COLUMN:
        return R.evolve({rows: R.addIndex(R.map)((row, rowIndex) => {
            if (R.path(["rowStatus", rowIndex, "status"], state) === "ok") {
                return row;
            }
            if (!action.override && getCellValue(row[action.columnIndex])) {
                return row;
            }

            const value = action.value === GENERATE_USERNAME
                ? generateUsername(rowIndex, state)
                : action.value;

            return updateIn([action.columnIndex, "customValue"], value, row);
        })}, state);
    case SET_USER_DATA:
        return updateIn(["userCache", action.username], R.always(R.pick(["state", "userData"], action)), state);
    case SET_ACTIVE_COLUMN_TYPES:
        return R.assoc("activeColumnTypes", action.columnTypes, state);
    default:
        return state;
    }
}

const isFirstName = R.equals(AllColumnTypes.first_name);
const isLastName = R.equals(AllColumnTypes.last_name);

const usernameSlugify = R.compose(
    // Allow _, - and . elsewhere and drop any other chars
    s => s.replace(/[^a-z0-9_\-\.]/g, ""),

    // Remove chars until the username starts with a-z
    s => s.replace(/^[^a-z]+/g, ""),

    // Swap Ä to A etc.
    cleanDiacritics,

    s => s.toLowerCase()
);

function generateUsername(rowIndex, state) {
    const firstNameIndex = R.findIndex(isFirstName, state.columns);
    const lastNameIndex = R.findIndex(isLastName, state.columns);
    const row = state.rows[rowIndex];
    return [firstNameIndex, lastNameIndex]
        .map(i => getCellValue(row[i]))
        .map(usernameSlugify)
        .join(".");
}

export default reducer;


