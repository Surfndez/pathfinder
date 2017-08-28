// pathfinder/client/src/app-controller.ts
//
// Copyright © 2017 The Pathfinder Project Developers.
//
// Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
// http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
// <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
// option. This file may not be copied, modified, or distributed
// except according to those terms.

import {ShaderLoader, ShaderMap, ShaderProgramSource} from './shader-loader';
import {expectNotNull} from './utils';

export default abstract class AppController<View> {
    constructor() {}

    start() {
        const canvas = document.getElementById('pf-canvas') as HTMLCanvasElement;

        const shaderLoader = new ShaderLoader;
        shaderLoader.load();

        this.view = Promise.all([shaderLoader.common, shaderLoader.shaders]).then(allShaders => {
            return this.createView(canvas, allShaders[0], allShaders[1]);
        });
    }

    protected loadFile() {
        const file = expectNotNull(this.loadFileButton.files, "No file selected!")[0];
        const reader = new FileReader;
        reader.addEventListener('loadend', () => {
            this.fileData = reader.result;
            this.fileLoaded();
        }, false);
        reader.readAsArrayBuffer(file);
    }

    protected abstract fileLoaded(): void;

    protected abstract createView(canvas: HTMLCanvasElement,
                                  commonShaderSource: string,
                                  shaderSources: ShaderMap<ShaderProgramSource>):
                                  View;

    view: Promise<View>;

    protected fileData: ArrayBuffer;

    protected canvas: HTMLCanvasElement;
    protected loadFileButton: HTMLInputElement;
}
