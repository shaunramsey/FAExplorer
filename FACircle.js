import { StatusBar } from 'expo-status-bar';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useState, Component } from 'react';



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



const Circle = (props) => {
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


export default function FACircle() {
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
      <StatusBar style="status" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    color: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  text: {
    color: '#fff',
  },
  circles: {
    flexDirection: 'row',
    display: 'flex',
  },
  circle: {
    justifyContent: 'center',
    textAlign: 'center',
    borderColor: '#f90',
    borderWidth: '1px',
    backgroundColor: '#fff',
    color: '#000',
    borderRadius: '50%',
    height: '50px',
    width: '50px',

  },
  circleText: {

  },
  buttonText: {
    color: '#fff',
    fontSize: '24px',
    fontWeight: 'bold',
  },
  status: {
    color: '#f0f',
  },
  button: {
    margin: '40px',
    paddingHorizontal: '30px',
    paddingTop: '1px',
    paddingBottom: '5px',
    borderColor: '#fff',
    borderStyle: 'solid',
    borderWidth: '2px',
    backgroundColor: '#383',
    borderRadius: '20px',

    color: '#afa',
    fontSize: '24px',
    fontWeight: '400',
  },
  inactive: {
    margin: '4px',
    borderWidth: '2px',
    borderColor: '#000',
    borderRadius: '50%',
    backgroundColor: '#fff',
  },
  active: {
    margin: '4px',
    borderWidth: '2px',
    borderColor: '#0ff',
    borderRadius: '50%',
    backgroundColor: '#fff',
  }
});



const getPadding = (inputPadding) => {
  let p = inputPadding.split(' ');
  return {
    paddingTop: p[0],
    paddingRight: p[1],
    paddingBottom: p[2],
    paddingLeft: p[3],
    borderColor: "#fff",
    borderWidth: "1px",
  };
}
const buttonStyle = StyleSheet.flatten([getPadding("10px 20px 30px 40px"), styles.button]);
