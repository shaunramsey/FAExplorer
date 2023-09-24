import { StatusBar } from 'expo-status-bar';
import { Text, TextInput, TouchableOpacity, View } from 'react-native';
import { styles } from "./Styles";
import { useState, Component } from 'react';
// import { TextInput } from 'react-native-gesture-handler';

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    // Update state so the next render will show the fallback UI.
    return { hasError: true, error: error };
  }

  componentDidCatch(error, info) {
    // Example "componentStack":
    //   in ComponentThatThrows (created by App)
    //   in ErrorBoundary (created by App)
    //   in div (created by App)
    //   in App
    // logErrorToMyService(error, info.componentStack);
    console.log(`error is ${error} stack is ${info.componentStack}`);
  }

  render() {
    if (this.state.hasError) {
      // You can render any custom fallback UI
      if (this.props.fallback != null && this.props.fallback != "") {
        return this.props.fallback;
      } else {
        return (<p> {this.state.error.toString()} </p>);
      }

    }
    // <ErrorBoundary fallback={<p>Problem in circle</p>}>
    return this.props.children;
  }
}

class Item {
  constructor() {
    this.name = "";
    this.dmg = 12;
  }

  static from(v) {
    let n = new Item();
    n.name = v.name;
    n.dmg = v.dmg;
    return n;
  }

  set(name, dmg) {
    this.name = name;
    this.dmg = dmg;
  }

  print(st) {
    console.log(`st: ${st}: name: ${this.name}   dmg: ${this.dmg}`);
  }

  clone(old) {
    this.name = old.name;
    this.dmg = old.dmg;
  }
}


export const Circle = (props) => {
  let v = new Item();
  v.set("help", 10);
  v.print("1");//
  let c = Object.create(v);
  //let c = Item.from(v);
  c.dmg = 12;
  c.name = "me";
  v.set("h2", 11);
  console.log("about to print c");
  c.print("2");
  v.print("3");
  // console.log(`active ${props.text} is ${props.active}`);
  // console.log(`${props.active != null}`);
  // console.log(`${props.active == true}`);
  const activeStyle = (props.active != null && (props.active == 'true' || props.active == true)) ? styles.active : styles.inactive;
  // console.log(`${activeStyle.borderColor}`);
  return (
    <View style={activeStyle}>
      <View style={styles.circle}>
        <Text style={styles.circleText}>{props.text}</Text>
      </View>
    </View>
  );
}

export const FACircle = (props) => {
  const [thisName, setThisName] = useState("DotWolf");
  const [size, setSize] = useState(0);
  const [activeState, setActiveState] = useState(0);

  const onPress = () => {
    setActiveState((activeState + 1) % 3);
    if (thisName == "Flux") {
      setThisName("DotWolf");
    } else {
      setThisName("Flux");
    }
  }

  const nextScreen = () => {
    props.navigation.push("Second");
  }

  return (
    <View style={styles.container}>
      <Text style={styles.text}>Hi {thisName}</Text>
      <Text style={styles.text}>Size is {size}</Text>
      <View style={styles.circles}>
        <Circle text="ttt" active={activeState == 0}></Circle>
        <Circle text="a" active={activeState == 1}></Circle>
        <Circle text="b" active={activeState == 2}></Circle>
      </View>
      <TouchableOpacity style={styles.button} onPress={onPress}>
        <Text style={styles.buttonText}>Press Me</Text>
      </TouchableOpacity>
      <TouchableOpacity style={styles.button} onPress={nextScreen}>
        <Text style={styles.buttonText}>Next Screen</Text>
      </TouchableOpacity>
      <StatusBar style="status" />
    </View>
  );
}



