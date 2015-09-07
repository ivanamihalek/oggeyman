package oggeyman;

public class Oggeyman {
       
    static {      	
    	// this should look for the static version of library when its burned into JVM
    	System.loadLibrary("oggeyman");
    }
    	
    // on the native side: pointer to C++ object on the heap
    private long nativeHandle; 
    //****************************************************************/
    private native long create();	
    public Oggeyman(){
    	nativeHandle = create(); // return the object handle
    }
    //****************************************************************/
    // we have private version of the native function for every function we are exporting
    private native boolean init(long nativeHandle, String string); 
    private native void timer_restart (long nativeHandle);
    private native boolean fast_forward_to_frame(long nativeHandle, int frameno);
    private native int width(long nativeHandle);
    private native int height(long nativeHandle);
    // this will provide BGRA pixel data for OpenGL texture
    private native boolean get_next_frame(long nativeHandle, byte [] BGRAbuffer); 
    private native boolean done(long nativeHandle);
    private native boolean shutdown(long nativeHandle);
	
    //****************************************************************/
	public boolean init(String path) {// path to ogg file
		return init(nativeHandle, path);
	}

	public void timer_restart() {
		timer_restart(nativeHandle); 
	}
	public boolean fast_forward_to_frame(int frameno) {
		return fast_forward_to_frame(nativeHandle, frameno);
	}
	public int width() {
		return width(nativeHandle);
	}
	public int height() {
		return height(nativeHandle);
	}	
	public boolean get_next_frame(byte [] BGRAbuffer) {// this will provide BGRA pixel data for OpenGL texture
		// Java char is 16-bit
		//  C and C++ the char data type is 8-bit characters, corresponding roughly to the Java byte type. 
		//  will have to somehow explain to C that BGRAbuffer.array() is actually char[]
		return get_next_frame(nativeHandle, BGRAbuffer);
	}
	public boolean done() {
		return done(nativeHandle);
	}
	public boolean shutdown() {
		return shutdown(nativeHandle);
	}
}
