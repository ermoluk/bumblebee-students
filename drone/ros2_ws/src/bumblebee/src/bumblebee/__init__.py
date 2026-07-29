import rclpy
from threading import Thread, Event

def long_callback(fn):
    """
    Decorator fixing a rclpy issue for long-running topic callbacks, primarily
    for image processing.

    Usage example:

    @long_callback
    def image_callback(msg):
        # perform image processing
        # ...

    node.create_subscription(Image, 'main_camera/image_raw', image_callback, 1)
    """
    e = Event()

    def thread():
        while rclpy.ok():
            e.wait()
            e.clear()
            fn(thread.current_msg)

    thread.current_msg = None
    Thread(target=thread, daemon=True).start()

    def wrapper(msg):
        thread.current_msg = msg
        e.set()

    return wrapper
