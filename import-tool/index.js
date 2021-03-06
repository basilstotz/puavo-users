const STATE_KEY = [
    "import-tool",
    window.location.toString(),
    /* global __webpack_hash__ */
    process.env.NODE_ENV === "production" ? __webpack_hash__ : "DEV",
].join(":");

require("babel-runtime/core-js/promise").default = require("bluebird");
window.Promise = require("bluebird"); // extra override
import "babel/polyfill";
import "whatwg-fetch";

import "./style.css";

import React from "react";
import ReactDOM from "react-dom";
import R from "ramda";
import {createStore, applyMiddleware, compose} from "redux";
import createLogger from "redux-logger";
import thunk from "redux-thunk";
import {Provider} from "react-redux";
import reducers from "./reducers";
import {batchedUpdatesMiddleware} from "redux-batched-updates";

import ImportTool from "./components/ImportTool";

import {SET_DEFAULT_SCHOOL} from "./constants";
import {AllColumnTypes} from "./ColumnTypes";
import createStateStorage from "./StateStorage";
import {fetchLegacyRoles, fetchGroups, setActiveColumnTypes} from "./actions";


const logger = createLogger({
    timestamp: false,
    duration: true,
    collapsed: true,
});

const createFinalStore = compose(
    createStateStorage(STATE_KEY),
    applyMiddleware(batchedUpdatesMiddleware, thunk, logger)
)(createStore);


function createImportTool({containerId, school, useGroupsOnly}) {
    var container = document.getElementById(containerId);
    const store = createFinalStore(reducers);

    store.dispatch({
        type: SET_DEFAULT_SCHOOL,
        school,
    });

    if (useGroupsOnly) {
        store.dispatch(setActiveColumnTypes(R.omit(["legacy_role"], AllColumnTypes)));
        store.dispatch(fetchGroups(school.id));
    } else {
        store.dispatch(setActiveColumnTypes(R.omit(["group"], AllColumnTypes)));
        store.dispatch(fetchLegacyRoles(school.id));
    }

    container.innerHTML = "";
    ReactDOM.render(
        <div>
            <Provider store={store}>
                <ImportTool />
            </Provider>
        </div>
    , container);
}

window.createImportTool = createImportTool;
