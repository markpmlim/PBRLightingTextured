//
//  ViewController.swift
//  PhysicallyBasedLighting
//
//  Created by Mark Lim Pak Mun on 01/11/2024.
//  Copyright © 2024 Mark Lim Pak Mun. All rights reserved.


class OpenGLViewController: NSViewController
{
    var glView: NSOpenGLView!
    var glContext: NSOpenGLContext!
    var _defaultFBOName: GLuint = 0
    var _displayLink: CVDisplayLink?

    var renderer: OpenGLRenderer?

    override func viewDidLoad()
    {
        super.viewDidLoad()
        glView = self.view as! NSOpenGLView

        prepareView()
        makeCurrentContext()
        let viewSizePoints = glView.bounds.size
        let viewSizePixels = glView.convertToBacking(viewSizePoints)

        renderer = OpenGLRenderer(_defaultFBOName, viewSize: viewSizePixels)
    }


    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


    let displayLinkOutputCallback: CVDisplayLinkOutputCallback = {
        (displayLink: CVDisplayLink, inNow: UnsafePointer<CVTimeStamp>,
         inOutputTime: UnsafePointer<CVTimeStamp>,
         flagsIn: CVOptionFlags,
         flagsOut: UnsafeMutablePointer<CVOptionFlags>,
         displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn in

        var currentTime = CVTimeStamp()
        CVDisplayLinkGetCurrentTime(displayLink, &currentTime)
        let fps = (currentTime.rateScalar * Double(currentTime.videoTimeScale) / Double(currentTime.videoRefreshPeriod))
        let viewController = unsafeBitCast(displayLinkContext,
                                           to: OpenGLViewController.self)

        viewController.draw(fps)
        return kCVReturnSuccess
    }

   
    func prepareView()
    {
        let displayMask = CGDisplayIDToOpenGLDisplayMask(CGMainDisplayID())

        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAColorSize), UInt32(32),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFADepthSize), UInt32(24),
            UInt32(NSOpenGLPFAScreenMask), displayMask,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        let pf = NSOpenGLPixelFormat(attributes: attrs)
        if (pf == nil) {
            Swift.print("Couldn't init OpenGL at all, sorry :(")
            abort()
        }

        glContext = NSOpenGLContext(format: pf!, share: nil)

        CGLLockContext(glContext.cglContextObj!)
        makeCurrentContext()
        CGLUnlockContext(glContext.cglContextObj!)

        //glEnable(GLenum(GL_FRAMEBUFFER_SRGB))
        glView.pixelFormat = pf
        glView.openGLContext = glContext
        glView.wantsBestResolutionOpenGLSurface = true

        // The default framebuffer object (FBO) is 0 on macOS, because it uses
        // a traditional OpenGL pixel format model. Might be different on other OSes.
        _defaultFBOName = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

        CVDisplayLinkSetOutputCallback(_displayLink!,
                                       displayLinkOutputCallback,
                                       UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        CVDisplayLinkStart(_displayLink!)
    }


    func makeCurrentContext()
    {
        glContext.makeCurrentContext()
    }


    override func viewDidLayout()
    {
        CGLLockContext(glContext.cglContextObj!)

        let viewSizePoints = glView.bounds.size
        let viewSizePixels = glView.convertToBacking(viewSizePoints)

        makeCurrentContext()

        renderer?.resize(viewSizePixels)

        CGLUnlockContext(glContext.cglContextObj!);

        if !CVDisplayLinkIsRunning(_displayLink!) {
            CVDisplayLinkStart(_displayLink!)
        }
    }

    override func viewWillDisappear()
    {
        CVDisplayLinkStop(_displayLink!)
    }

    deinit
    {
        CVDisplayLinkStop(_displayLink!)
    }

    fileprivate func draw(_ framesPerSecond: Double)
    {
        CGLLockContext(glContext.cglContextObj!);

        makeCurrentContext()
        // The method might be called before the renderer object is instantiated.
        // To avoid a crash, append a ? to the OpenGLRenderer instance
        renderer?.draw(framesPerSecond)

        CGLFlushDrawable(glContext.cglContextObj!);
        CGLUnlockContext(glContext.cglContextObj!);
    }

    override func viewDidAppear()
    {
        self.glView.window!.makeFirstResponder(self)
    }

    // Do we have to convert from points to pixels?
    override func mouseDown(with event: NSEvent)
    {
        let mouseLocation = self.glView.convert(event.locationInWindow,
                                                from: nil)
        renderer?.camera.startDragging(from: mouseLocation)
    }

    override func mouseDragged(with event: NSEvent)
    {
        let mouseLocation = self.glView.convert(event.locationInWindow,
                                                from: nil)
        if (renderer?.camera.isDragging)! {
            renderer?.camera.drag(to: mouseLocation)
        }
    }

    override func mouseUp(with event: NSEvent)
    {
        let mouseLocation = self.glView.convert(event.locationInWindow,
                                                from: nil)
        renderer?.camera.endDrag()
    }

    override func scrollWheel(with event: NSEvent)
    {
        let dz = event.scrollingDeltaY
        renderer?.camera.zoom(inOrOut: Float(dz))
    }

}
