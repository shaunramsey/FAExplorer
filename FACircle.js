import { StatusBar } from 'expo-status-bar';
import { Text, TextInput, TouchableOpacity, View, SafeAreaView, } from 'react-native';
import { GLView } from 'expo-gl'
import Expo2DContext from 'expo-2d-context';
import { styles } from "./Styles";
import { useState, Component } from 'react';
// import { TextInput } from 'react-native-gesture-handler';




export class FACircle extends Component {

  onCreateContext = (gl) => {
    var ctx = new Expo2DContext(gl);
    console.log("onCreateContext");
    ctx.translate(50, 200);
    ctx.scale(4, 4);
    ctx.fillStyle = "grey";
    ctx.fillRect(20, 40, 100, 100);
    ctx.fillStyle = "white";
    ctx.fillRect(30, 100, 20, 30);
    ctx.fillRect(60, 100, 20, 30);
    ctx.fillRect(90, 100, 20, 30);
    ctx.beginPath();
    ctx.arc(50, 70, 18, 0, 2 * Math.PI);
    ctx.arc(90, 70, 18, 0, 2 * Math.PI);
    ctx.fill();
    ctx.fillStyle = "grey";
    ctx.beginPath();
    ctx.arc(50, 70, 8, 0, 2 * Math.PI);
    ctx.arc(90, 70, 8, 0, 2 * Math.PI);
    ctx.fill();
    ctx.strokeStyle = "black";
    ctx.beginPath();
    ctx.moveTo(70, 40);
    ctx.lineTo(70, 30);
    ctx.arc(70, 20, 10, 0.5 * Math.PI, 2.5 * Math.PI);
    ctx.stroke();
    ctx.flush();
    return;
    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    gl.clearColor(0, 1, 1, 1);

    // Create vertex shader (shape & position)
    const vert = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(
      vert,
      `
    void main(void) {
      gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
      gl_PointSize = 150.0;
    }
  `
    );
    gl.compileShader(vert);

    // Create fragment shader (color)
    const frag = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(
      frag,
      `
      void main(void) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
      }
     `
    );
    gl.compileShader(frag);

    // Link together into a program
    const program = gl.createProgram();
    gl.attachShader(program, vert);
    gl.attachShader(program, frag);
    gl.linkProgram(program);
    gl.useProgram(program);

    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.POINTS, 0, 1);

    gl.flush();
    gl.endFrameEXP();
  }

  onCreateContext2 = (gl) => {
    console.log("oncreate context");
    var ctx = new Expo2DContext(gl);
    ctx.translate(50, 200)
    ctx.scale(4, 4)
    ctx.fillStyle = "grey";
    ctx.fillRect(20, 40, 100, 100);
    ctx.fillStyle = "white";
    ctx.fillRect(30, 100, 20, 30);
    ctx.fillRect(60, 100, 20, 30);
    ctx.fillRect(90, 100, 20, 30);
    ctx.beginPath();
    ctx.arc(50, 70, 18, 0, 2 * Math.PI);
    ctx.arc(90, 70, 18, 0, 2 * Math.PI);
    ctx.fill();
    ctx.fillStyle = "grey";
    ctx.beginPath();
    ctx.arc(50, 70, 8, 0, 2 * Math.PI);
    ctx.arc(90, 70, 8, 0, 2 * Math.PI);
    ctx.fill();
    ctx.strokeStyle = "black";
    ctx.beginPath();
    ctx.moveTo(70, 40);
    ctx.lineTo(70, 30);
    ctx.arc(70, 20, 10, 0.5 * Math.PI, 2.5 * Math.PI);
    ctx.stroke();
    ctx.flush();
  }

  render() {
    console.log("Rendder FACircle component");
    return (

      <View style={{ flex: 1, border: 5, borderColor: 'white', backgroundColor: 'black' }}>
        <GLView style={{ width: 300, height: 300 }} onContextCreate={this.onCreateContext} />
      </View >

    );
  }
}



